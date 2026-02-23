defmodule SferaDoc.Pdf.HotCache do
  @moduledoc """
  Fast, ephemeral hot cache for rendered PDF binaries.

  Sits in front of the object store to serve repeat requests with minimal latency.
  Supports two backends:

  - **`:redis`**: Distributed, suitable for multi-node deployments. Starts its own
    named Redix connection independent of the template store connection.
  - **`:ets`**: Process-local ETS table. Zero external dependencies, suitable for
    single-node deployments or development.

  **Disabled by default.** Enable via:

      # Redis backend
      config :sfera_doc, :pdf_hot_cache,
        adapter: :redis,
        ttl: 60           # seconds

      # ETS backend
      config :sfera_doc, :pdf_hot_cache,
        adapter: :ets,
        ttl: 300

  The Redis backend reuses `config :sfera_doc, :redis` by default. Override with:

      config :sfera_doc, :pdf_hot_cache,
        adapter: :redis,
        ttl: 60,
        redis: [host: "cache.host", port: 6379]

  > #### Memory Warning {: .warning}
  >
  > PDFs can be 100 KB – 10 MB or more. Keep TTLs short and monitor memory.
  > For Redis, set `maxmemory-policy allkeys-lru`.
  """

  use GenServer

  @redis_conn __MODULE__
  @ets_table :sfera_doc_pdf_hot_cache
  @redis_prefix "sfera_doc:pdf"

  # ---------------------------------------------------------------------------
  # Supervisor integration
  # ---------------------------------------------------------------------------

  @doc "Returns a child spec if the hot cache is enabled, `nil` otherwise."
  def worker_spec do
    case adapter() do
      nil -> nil
      _ ->
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, []},
          type: :worker,
          restart: :permanent
        }
    end
  end

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns `{:ok, pdf_binary}` on a cache hit within TTL, `:miss` otherwise.
  Always returns `:miss` when the hot cache is disabled.
  """
  @spec get(String.t(), pos_integer(), String.t()) :: {:ok, binary()} | :miss
  def get(name, version, hash) do
    case adapter() do
      nil -> :miss
      :redis -> redis_get(name, version, hash)
      :ets -> ets_get(name, version, hash)
    end
  end

  @doc """
  Stores a rendered PDF binary. No-op when the hot cache is disabled.
  Failures are silently swallowed — the caller always receives the PDF.
  """
  @spec put(String.t(), pos_integer(), String.t(), binary()) :: :ok
  def put(name, version, hash, binary) do
    case adapter() do
      nil -> :ok
      :redis -> redis_put(name, version, hash, binary)
      :ets -> ets_put(name, version, hash, binary)
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer (ETS + Redis connection)
  # ---------------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, adapter(), name: __MODULE__)
  end

  @impl GenServer
  def init(:ets) do
    :ets.new(@ets_table, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, :ets}
  end

  def init(:redis) do
    opts = redis_opts()
    {:ok, _pid} = Redix.start_link(opts ++ [name: @redis_conn])
    {:ok, :redis}
  end

  @impl GenServer
  def handle_call({:ets_put, name, version, hash, binary}, _from, state) do
    now = System.monotonic_time(:second)
    :ets.insert(@ets_table, {{name, version, hash}, binary, now})
    {:reply, :ok, state}
  end

  # ---------------------------------------------------------------------------
  # Redis helpers
  # ---------------------------------------------------------------------------

  defp redis_get(name, version, hash) do
    key = redis_key(name, version, hash)

    case Redix.command(@redis_conn, ["GET", key]) do
      {:ok, nil} -> :miss
      {:ok, binary} -> {:ok, binary}
      {:error, _} -> :miss
    end
  end

  defp redis_put(name, version, hash, binary) do
    ttl = hot_cache_ttl()
    key = redis_key(name, version, hash)

    case Redix.command(@redis_conn, ["SET", key, binary, "EX", ttl]) do
      {:ok, _} -> :ok
      {:error, _} -> :ok
    end
  end

  defp redis_key(name, version, hash), do: "#{@redis_prefix}:#{name}:#{version}:#{hash}"

  # ---------------------------------------------------------------------------
  # ETS helpers
  # ---------------------------------------------------------------------------

  defp ets_get(name, version, hash) do
    ttl = hot_cache_ttl()
    now = System.monotonic_time(:second)
    key = {name, version, hash}

    case :ets.lookup(@ets_table, key) do
      [{^key, binary, stored_at}] when now - stored_at < ttl -> {:ok, binary}
      _ -> :miss
    end
  end

  defp ets_put(name, version, hash, binary) do
    GenServer.call(__MODULE__, {:ets_put, name, version, hash, binary})
  end

  # ---------------------------------------------------------------------------
  # Config helpers
  # ---------------------------------------------------------------------------

  defp adapter do
    Application.get_env(:sfera_doc, :pdf_hot_cache, [])[:adapter]
  end

  defp hot_cache_ttl do
    Application.get_env(:sfera_doc, :pdf_hot_cache, []) |> Keyword.get(:ttl, 60)
  end

  defp redis_opts do
    case Application.get_env(:sfera_doc, :pdf_hot_cache, [])[:redis] do
      nil -> normalize_redis_opts(Application.get_env(:sfera_doc, :redis, host: "localhost", port: 6379))
      opts -> normalize_redis_opts(opts)
    end
  end

  defp normalize_redis_opts(opts) when is_binary(opts), do: [url: opts]
  defp normalize_redis_opts(opts) when is_list(opts), do: opts
end
