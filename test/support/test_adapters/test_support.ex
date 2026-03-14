defmodule SferaDoc.TestSupport do
  @moduledoc false

  @counters_table :sfera_doc_test_counters

  def reset_counters do
    case :ets.whereis(@counters_table) do
      :undefined ->
        :ets.new(@counters_table, [:set, :public, :named_table])

      _ ->
        :ets.delete_all_objects(@counters_table)
    end

    :ok
  end

  def increment(key) do
    ensure_counters_table()
    :ets.update_counter(@counters_table, key, {2, 1}, {key, 0})
    :ok
  end

  def get_counter(key) do
    ensure_counters_table()

    case :ets.lookup(@counters_table, key) do
      [{^key, count}] -> count
      _ -> 0
    end
  end

  defp ensure_counters_table do
    if :ets.whereis(@counters_table) == :undefined do
      :ets.new(@counters_table, [:set, :public, :named_table])
    end
  end
end
