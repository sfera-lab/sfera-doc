if Code.ensure_loaded?(Ecto.Adapters.SQL) do
  defmodule SferaDoc.EctoCase do
    @moduledoc false
    use ExUnit.CaseTemplate

    using do
      quote do
        import SferaDoc.EctoCase
      end
    end

    setup do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: SferaDoc.TestRepo
      )

      Application.put_env(:sfera_doc, :cache, enabled: false)

      :ok = Ecto.Adapters.SQL.Sandbox.checkout(SferaDoc.TestRepo)

      :ok
    end
  end
end
