defmodule SferaDoc.Store.ETS do
  @moduledoc """
  ETS-backed in-memory storage adapter for SferaDoc.

  > #### Development and testing only {: .warning}
  >
  > This adapter stores templates in a BEAM ETS table. All data is lost on
  > process crash or node restart. Use only for development and testing.

  ## Configuration

      config :sfera_doc, :store,
        adapter: SferaDoc.Store.ETS
  """

  @behaviour SferaDoc.Store.Adapter

  use GenServer

  @table :sfera_doc_store_ets

  # ---------------------------------------------------------------------------
  # Adapter callbacks
  # ---------------------------------------------------------------------------

  @impl SferaDoc.Store.Adapter
  def worker_spec do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :worker,
      restart: :permanent
    }
  end

  @impl SferaDoc.Store.Adapter
  def get(name) do
    case active_template(name) do
      nil -> {:error, :not_found}
      template -> {:ok, template}
    end
  end

  @impl SferaDoc.Store.Adapter
  def get_version(name, version) do
    case :ets.lookup(@table, {name, version}) do
      [{_key, _v, template}] -> {:ok, template}
      [] -> {:error, :not_found}
    end
  end

  @impl SferaDoc.Store.Adapter
  def put(template) do
    GenServer.call(__MODULE__, {:put, template})
  end

  @impl SferaDoc.Store.Adapter
  def list do
    templates =
      :ets.tab2list(@table)
      |> Enum.map(fn {_key, _v, t} -> t end)
      |> Enum.filter(& &1.is_active)
      |> Enum.sort_by(& &1.name)

    {:ok, templates}
  end

  @impl SferaDoc.Store.Adapter
  def list_versions(name) do
    templates =
      :ets.match_object(@table, {{name, :_}, :_, :_})
      |> Enum.map(fn {_key, _v, t} -> t end)
      |> Enum.sort_by(& &1.version, :desc)

    {:ok, templates}
  end

  @impl SferaDoc.Store.Adapter
  def activate_version(name, version) do
    GenServer.call(__MODULE__, {:activate_version, name, version})
  end

  @impl SferaDoc.Store.Adapter
  def delete(name) do
    GenServer.call(__MODULE__, {:delete, name})
  end

  @doc "Clears all entries: test helper only."
  def reset, do: GenServer.call(__MODULE__, :reset)

  # ---------------------------------------------------------------------------
  # GenServer
  # ---------------------------------------------------------------------------

  def start_link(_opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl GenServer
  def init(:ok) do
    :ets.new(@table, [:set, :protected, :named_table, read_concurrency: true])
    {:ok, %{}}
  end

  @impl GenServer
  def handle_call({:put, template}, _from, state) do
    # Deactivate all current active versions for this name
    deactivate_all(template.name)

    # Compute next version
    next_v = next_version(template.name)
    new_template = %{template | version: next_v, is_active: true}
    :ets.insert(@table, {{template.name, next_v}, next_v, new_template})

    {:reply, {:ok, new_template}, state}
  end

  def handle_call({:activate_version, name, version}, _from, state) do
    case :ets.lookup(@table, {name, version}) do
      [] ->
        {:reply, {:error, :not_found}, state}

      [{_key, _v, template}] ->
        deactivate_all(name)
        updated = %{template | is_active: true}
        :ets.insert(@table, {{name, version}, version, updated})
        {:reply, {:ok, updated}, state}
    end
  end

  def handle_call({:delete, name}, _from, state) do
    :ets.match_delete(@table, {{name, :_}, :_, :_})
    {:reply, :ok, state}
  end

  def handle_call(:reset, _from, state) do
    :ets.delete_all_objects(@table)
    {:reply, :ok, state}
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp active_template(name) do
    :ets.match_object(@table, {{name, :_}, :_, :_})
    |> Enum.map(fn {_k, _v, t} -> t end)
    |> Enum.find(& &1.is_active)
  end

  defp next_version(name) do
    case :ets.match_object(@table, {{name, :_}, :_, :_}) do
      [] -> 1
      objects -> objects |> Enum.map(fn {_k, v, _t} -> v end) |> Enum.max() |> Kernel.+(1)
    end
  end

  defp deactivate_all(name) do
    :ets.match_object(@table, {{name, :_}, :_, :_})
    |> Enum.each(fn {{n, v}, _ver, template} ->
      :ets.insert(@table, {{n, v}, v, %{template | is_active: false}})
    end)
  end
end
