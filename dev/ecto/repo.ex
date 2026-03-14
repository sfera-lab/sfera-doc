
case Application.get_env(:sfera_doc, :store, [])[:adapter] do
  SferaDoc.Store.Ecto ->
    defmodule SferaDoc.Dev.Repo do
      @moduledoc false

      use Ecto.Repo,
        otp_app: :sfera_doc,
        adapter: Ecto.Adapters.Postgres
    end

  _ ->
    :ok
end
