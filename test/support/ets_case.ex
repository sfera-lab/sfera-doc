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

    # Start ETS store if not running; otherwise reset its data
    case Process.whereis(SferaDoc.Store.ETS) do
      nil -> {:ok, _} = start_supervised(SferaDoc.Store.ETS)
      _pid -> SferaDoc.Store.ETS.reset()
    end

    :ok
  end
end
