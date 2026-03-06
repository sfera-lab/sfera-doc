
if SferaDoc.Config.store_adapter() == SferaDoc.Store.Ecto do
  defmodule SferaDoc.Dev.Repo do
    @moduledoc false

    use Ecto.Repo,
      otp_app: :sfera_doc,
      adapter: Ecto.Adapters.Postgres
  end
end
