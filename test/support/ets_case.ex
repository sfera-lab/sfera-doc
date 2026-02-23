defmodule SferaDoc.ETSCase do
  @moduledoc false
  use ExUnit.CaseTemplate

  using do
    quote do
      import SferaDoc.ETSCase
    end
  end

  setup do
    Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
    Application.put_env(:sfera_doc, :cache, enabled: false)

    # Start ETS store if not running
    case Process.whereis(SferaDoc.Store.ETS) do
      nil ->
        {:ok, _} = start_supervised(SferaDoc.Store.ETS)

      _pid ->
        # Clean existing data
        :ets.delete_all_objects(:sfera_doc_store_ets)
    end

    :ok
  end
end
