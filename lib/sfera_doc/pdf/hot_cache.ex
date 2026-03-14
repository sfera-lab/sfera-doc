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

  @redis_conn Module.concat(__MODULE__, Redis)
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
    case GenServer.start_link(__MODULE__, adapter(), name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl GenServer
  def init(:ets) do
    :ets.new(@ets_table, [
      :set,
      :public,
      :named_table,
      read_concurrency: true,
      write_concurrency: true
    ])

    schedule_sweep()
    {:ok, :ets}
  end

  def init(:redis) do
    opts = redis_opts()

    case Redix.start_link(opts ++ [name: @redis_conn]) do
      {:ok, _pid} ->
        {:ok, :redis}

      {:error, {:already_started, _pid}} ->
        {:ok, :redis}

      {:error, reason} ->
        {:stop, reason}
    end
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

    case safe_redis_command(["GET", key]) do
      {:ok, nil} ->
        :miss

      {:ok, binary} ->
        {:ok, binary}

      {:error, reason} ->
        Logger.warning("SferaDoc.Pdf.HotCache: Redis get failed for #{key}: #{inspect(reason)}")
        :miss
    end
  end

  defp redis_put(name, version, hash, binary) do
    ttl = hot_cache_ttl()
    key = redis_key(name, version, hash)

    case safe_redis_command(["SET", key, binary, "EX", ttl]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning("SferaDoc.Pdf.HotCache: Redis put failed for #{key}: #{inspect(reason)}")
        :ok
    end
  end

  defp redis_key(name, version, hash), do: "#{@redis_prefix}:#{name}:#{version}:#{hash}"

  defp safe_redis_command(cmd) do
    try do
      Redix.command(@redis_conn, cmd)
    catch
      :exit, reason -> {:error, reason}
    end
  end

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

  defp normalize_redis_opts(opts) when is_binary(opts) do
    uri = URI.parse(opts)

    unless uri.scheme in ["redis", "rediss"] and uri.host do
      raise ArgumentError, "invalid redis URL: #{inspect(opts)}"
    end

    {username, password} =
      case uri.userinfo do
        nil -> {nil, nil}
        userinfo -> parse_userinfo(userinfo)
      end

    database =
      case uri.path do
        nil -> nil
        "" -> nil
        "/" -> nil
        path -> parse_database(path)
      end

    base_opts =
      [
        host: uri.host,
        port: uri.port || 6379
      ]
      |> maybe_put(:username, username)
      |> maybe_put(:password, password)
      |> maybe_put(:database, database)

    if uri.scheme == "rediss" do
      Keyword.put(base_opts, :ssl, true)
    else
      base_opts
    end
  end

  defp normalize_redis_opts({host, port}), do: [host: host, port: port]
  defp normalize_redis_opts(opts) when is_list(opts), do: opts

  defp parse_userinfo(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user] -> {user, nil}
      [user, pass] -> {user, pass}
    end
  end

  defp parse_database(path) do
    db = String.trim_leading(path, "/")

    case Integer.parse(db) do
      {int, ""} -> int
      _ -> raise ArgumentError, "invalid redis database in URL path: #{inspect(path)}"
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  @doc false
  def redis_conn_name, do: @redis_conn
end
