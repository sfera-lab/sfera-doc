if Code.ensure_loaded?(Ecto.Adapters.SQLite3) do
  defmodule SferaDoc.TestRepo do
    use Ecto.Repo,
      otp_app: :sfera_doc,
      adapter: Ecto.Adapters.SQLite3
  end
end
