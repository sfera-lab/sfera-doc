defmodule SferaDoc.TestStore do
  @moduledoc false
  @behaviour SferaDoc.Store.Adapter

  alias SferaDoc.Template

  @table :sfera_doc_test_store

  @impl true
  def worker_spec, do: nil

  def reset do
    case :ets.whereis(@table) do
      :undefined -> :ok
      _ -> :ets.delete(@table)
    end

    :ok
  end

  @impl true
  def get(name) do
    ensure_table()

    case active_for(name) do
      nil -> {:error, :not_found}
      template -> {:ok, template}
    end
  end

  @impl true
  def get_version(name, version) do
    ensure_table()

    case :ets.lookup(@table, {name, version}) do
      [{{^name, ^version}, template}] -> {:ok, template}
      _ -> {:error, :not_found}
    end
  end

  @impl true
  def put(%Template{name: name, body: body, variables_schema: variables_schema}) do
    ensure_table()

    versions = versions_for(name)
    next_version = next_version(versions)

    now = DateTime.utc_now()

    versions
    |> Enum.map(fn t -> %{t | is_active: false} end)
    |> Enum.each(fn t -> :ets.insert(@table, {{t.name, t.version}, t}) end)

    template = %Template{
      id: "test-#{name}-#{next_version}",
      name: name,
      body: body,
      version: next_version,
      is_active: true,
      variables_schema: variables_schema,
      inserted_at: now,
      updated_at: now
    }

    :ets.insert(@table, {{name, next_version}, template})
    {:ok, template}
  end

  @impl true
  def list do
    ensure_table()

    templates =
      @table
      |> :ets.tab2list()
      |> Enum.map(fn {{_name, _version}, template} -> template end)
      |> Enum.filter(& &1.is_active)

    {:ok, templates}
  end

  @impl true
  def list_versions(name) do
    ensure_table()
    {:ok, versions_for(name)}
  end

  @impl true
  def activate_version(name, version) do
    ensure_table()

    case :ets.lookup(@table, {name, version}) do
      [] ->
        {:error, :not_found}

      [{{^name, ^version}, template}] ->
        versions_for(name)
        |> Enum.map(fn t ->
          if t.version == version, do: %{t | is_active: true}, else: %{t | is_active: false}
        end)
        |> Enum.each(fn t -> :ets.insert(@table, {{t.name, t.version}, t}) end)

        {:ok, %{template | is_active: true}}
    end
  end

  @impl true
  def delete(name) do
    ensure_table()

    @table
    |> :ets.tab2list()
    |> Enum.each(fn {{t_name, version}, _template} ->
      if t_name == name, do: :ets.delete(@table, {t_name, version})
    end)

    :ok
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end
  end

  defp versions_for(name) do
    @table
    |> :ets.tab2list()
    |> Enum.map(fn {{_name, _version}, template} -> template end)
    |> Enum.filter(&(&1.name == name))
    |> Enum.sort_by(& &1.version, :desc)
  end

  defp active_for(name) do
    versions_for(name) |> Enum.find(& &1.is_active)
  end

  defp next_version([]), do: 1
  defp next_version(versions), do: versions |> Enum.map(& &1.version) |> Enum.max() |> Kernel.+(1)
end
