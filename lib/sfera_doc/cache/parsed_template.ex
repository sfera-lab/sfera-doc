defmodule SferaDoc.Cache.ParsedTemplate do
  @moduledoc """
  ETS-backed cache for parsed Solid template ASTs.

  Parsing a Liquid template with `Solid.parse/1` is a CPU-bound operation.
  This cache stores the parsed AST (a few KB) per `{name, version}` pair
  so subsequent renders of the same template version skip parsing entirely.

  The cache is enabled by default with a 300-second TTL. Configure via:

      config :sfera_doc, :cache,
        enabled: true,
        ttl: 300

  ## Reads

  Reads bypass the GenServer and query ETS directly for maximum throughput.
  Writes and invalidations are serialized through the GenServer to prevent
  race conditions on the ETS table.
  """

  use GenServer

  @table :sfera_doc_ast_cache
  @table_opts [:set, :protected, :named_table, read_concurrency: true]

  # ---------------------------------------------------------------------------
  # Supervisor integration
  # ---------------------------------------------------------------------------

  @doc "Returns a child spec for the supervisor, or `nil` if caching is disabled."
  def worker_spec do
    if SferaDoc.Config.cache_enabled?() do
      %{
        id: __MODULE__,
        start: {__MODULE__, :start_link, []},
        type: :worker,
        restart: :permanent
      }
    else
      nil
    end
  end

  # ---------------------------------------------------------------------------
  # Public API (called from Renderer)
  # ---------------------------------------------------------------------------

  @doc """
  Returns `{:ok, ast}` on cache hit within TTL, `:miss` otherwise.
  Reads ETS directly — no GenServer call overhead.
  """
  @spec get(String.t(), pos_integer()) :: {:ok, term()} | :miss
  def get(name, version) do
    ttl = SferaDoc.Config.cache_ttl()
    now = System.monotonic_time(:second)
    key = {name, version}

    case :ets.lookup(@table, key) do
      [{^key, ast, stored_at}] when now - stored_at < ttl -> {:ok, ast}
      _ -> :miss
    end
  end

  @doc "Stores a parsed AST in the cache. Serialized through GenServer."
  @spec put(String.t(), pos_integer(), term()) :: :ok
  def put(name, version, ast) do
    if SferaDoc.Config.cache_enabled?() do
      GenServer.call(__MODULE__, {:put, name, version, ast})
    else
      :ok
    end
  end

  @doc "Removes a specific `{name, version}` entry from the cache."
  @spec invalidate(String.t(), pos_integer()) :: :ok
  def invalidate(name, version) do
    if SferaDoc.Config.cache_enabled?() do
      GenServer.call(__MODULE__, {:invalidate, name, version})
    else
      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, @table_opts)
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:put, name, version, ast}, _from, state) do
    :ets.insert(@table, {{name, version}, ast, System.monotonic_time(:second)})
    {:reply, :ok, state}
  end

  def handle_call({:invalidate, name, version}, _from, state) do
    :ets.delete(@table, {name, version})
    {:reply, :ok, state}
  end
end
