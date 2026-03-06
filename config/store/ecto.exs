import Config

config :sfera_doc,
  ecto_repos: [SferaDoc.Dev.Repo]

config :sfera_doc, SferaDoc.Dev.Repo,
  database: "sfera_doc_dev",
  hostname: "localhost",
  port: 5432,
  username: "postgres",
  password: "postgres",
  pool_size: 10

config :sfera_doc, :store,
  adapter: SferaDoc.Store.Ecto,
  repo: SferaDoc.Dev.Repo
