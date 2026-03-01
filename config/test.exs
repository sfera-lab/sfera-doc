import Config

config :sfera_doc, :store, adapter: SferaDoc.Store.ETS
config :sfera_doc, :cache, enabled: false
config :sfera_doc, :chromic_pdf, disabled: true

# Ecto test repo (SQLite, used by mix test.ecto)
config :sfera_doc, ecto_repos: [SferaDoc.TestRepo]

config :sfera_doc, SferaDoc.TestRepo,
  database: Path.expand("../priv/test_repo/test.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5
