defmodule SferaDoc.TestObjectStore do
  @moduledoc false
  @behaviour SferaDoc.Pdf.ObjectStore.Adapter

  alias SferaDoc.TestSupport

  @table :sfera_doc_test_object_store

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
  def get(name, version, hash) do
    ensure_table()
    TestSupport.increment(:object_store_get)

    case :ets.lookup(@table, {name, version, hash}) do
      [{{^name, ^version, ^hash}, binary}] -> {:ok, binary}
      _ -> :miss
    end
  end

  @impl true
  def put(name, version, hash, binary) do
    ensure_table()
    TestSupport.increment(:object_store_put)
    :ets.insert(@table, {{name, version, hash}, binary})
    :ok
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      :ets.new(@table, [:set, :public, :named_table, read_concurrency: true])
    end
  end
end
