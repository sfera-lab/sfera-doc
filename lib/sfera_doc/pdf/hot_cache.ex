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

  require Logger

  @redis_conn __MODULE__
  @ets_table :sfera_doc_pdf_hot_cache
  @redis_prefix "sfera_doc:pdf"
  @sweep_interval_ms 60_000

  # ---------------------------------------------------------------------------
  # Supervisor integration
  # ---------------------------------------------------------------------------

  @doc "Returns a child spec if the hot cache is enabled, `nil` otherwise."
  def worker_spec do
    case adapter() do
      nil ->
        nil

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
    :ets.new(@ets_table, [:set, :public, :named_table, read_concurrency: true, write_concurrency: true])
    schedule_sweep()
    {:ok, :ets}
  end

  def init(:redis) do
    opts = redis_opts()
    {:ok, _pid} = Redix.start_link(opts ++ [name: @redis_conn])
    {:ok, :redis}
  end

  @impl GenServer
  def handle_info(:sweep, :ets = state) do
    evict_expired()
    schedule_sweep()
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # ---------------------------------------------------------------------------
  # Redis helpers
  # ---------------------------------------------------------------------------

  defp redis_get(name, version, hash) do
    key = redis_key(name, version, hash)

    case Redix.command(@redis_conn, ["GET", key]) do
      {:ok, nil} -> :miss
      {:ok, binary} -> {:ok, binary}
      {:error, reason} ->
        Logger.warning("SferaDoc.Pdf.HotCache: Redis get failed for #{key}: #{inspect(reason)}")
        :miss
    end
  end

  defp redis_put(name, version, hash, binary) do
    ttl = hot_cache_ttl()
    key = redis_key(name, version, hash)

    case Redix.command(@redis_conn, ["SET", key, binary, "EX", ttl]) do
      {:ok, _} -> :ok
      {:error, reason} ->
        Logger.warning("SferaDoc.Pdf.HotCache: Redis put failed for #{key}: #{inspect(reason)}")
        :ok
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
    now = System.monotonic_time(:second)
    :ets.insert(@ets_table, {{name, version, hash}, binary, now})
    :ok
  end

  defp evict_expired do
    ttl = hot_cache_ttl()
    now = System.monotonic_time(:second)

    :ets.select_delete(@ets_table, [
      {
        {:_, :_, :"$1"},
        [{:>=, {:-, {:const, now}, :"$1"}, {:const, ttl}}],
        [true]
      }
    ])
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval_ms)
  end

  # ---------------------------------------------------------------------------
  # Config helpers
  # ---------------------------------------------------------------------------

  defp adapter do
    SferaDoc.Config.pdf_hot_cache_adapter()
  end

  defp hot_cache_ttl do
    SferaDoc.Config.pdf_hot_cache_ttl()
  end

  defp redis_opts do
    case Application.get_env(:sfera_doc, :pdf_hot_cache, [])[:redis] do
      nil -> normalize_redis_opts(SferaDoc.Config.redis_config())
      opts -> normalize_redis_opts(opts)
    end
  end

  defp normalize_redis_opts(opts) when is_binary(opts), do: [url: opts]
  defp normalize_redis_opts(opts) when is_list(opts), do: opts
end
