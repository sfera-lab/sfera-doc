defmodule SferaDoc.TestRepo do
  @moduledoc """
  Test repository for Ecto-based tests.
  Uses SQLite3 in-memory database for fast test execution.
  """
  use Ecto.Repo,
    otp_app: :sfera_doc,
    adapter: Ecto.Adapters.SQLite3
end
