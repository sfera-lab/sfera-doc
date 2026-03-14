defmodule SferaDoc.Cache.ParsedTemplate do
  @moduledoc """
  Internal ETS-backed cache for parsed Solid template ASTs.

  Parsing a Liquid template with `Solid.parse/1` is a CPU-bound operation.
  This cache stores the parsed AST (a few KB) per `{name, version}` pair
  so subsequent renders of the same template version skip parsing entirely.

  The cache is enabled by default with a 300-second TTL. Configure via:

      config :sfera_doc, :cache,
        enabled: true,
        ttl: 300
  """

  use GenServer

  @table :sfera_doc_ast_cache
  @table_opts [:set, :protected, :named_table, read_concurrency: true]

  @doc false
  def worker_spec do
    cond do
      SferaDoc.Config.cache_enabled?() ->
        %{
          id: __MODULE__,
          start: {__MODULE__, :start_link, []},
          type: :worker,
          restart: :permanent
        }

      true ->
        nil
    end
  end

  #  Reads bypass the GenServer and query ETS directly for maximum throughput.
  #  Writes and invalidations are serialised through the GenServer to prevent
  #  race conditions on the ETS table.
  @doc false
  @spec get(String.t(), pos_integer()) :: {:ok, term()} | :miss
  def get(name, version) do
    cond do
      SferaDoc.Config.cache_enabled?() ->
        do_get(name, version)

      true ->
        :miss
    end
  end

  defp do_get(name, version) do
    ttl = SferaDoc.Config.cache_ttl()
    now = System.monotonic_time(:second)
    key = {name, version}

    case :ets.lookup(@table, key) do
      [{^key, ast, stored_at}] when now - stored_at < ttl -> {:ok, ast}
      _ -> :miss
    end
  end

  # The GenServer serialises writes to the ETS table to ensure consistency.
  @doc false
  @spec put(String.t(), pos_integer(), term()) :: :ok
  def put(name, version, ast) do
    cond do
      SferaDoc.Config.cache_enabled?() ->
        GenServer.call(__MODULE__, {:put, name, version, ast})

      true ->
        :ok
    end
  end

  @doc false
  @spec invalidate(String.t(), pos_integer()) :: :ok
  def invalidate(name, version) do
    cond do
      SferaDoc.Config.cache_enabled?() ->
        GenServer.call(__MODULE__, {:invalidate, name, version})

      true ->
        :ok
    end
  end

  def start_link(_opts \\ []) do
    case GenServer.start_link(__MODULE__, :ok, name: __MODULE__) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
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
