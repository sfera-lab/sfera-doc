import Config

# Example configuration — override in your app's config.exs:
#
# config :sfera_doc, :store,
#   adapter: SferaDoc.Store.Ecto,
#   repo: MyApp.Repo
#
# config :sfera_doc, :cache,
#   enabled: true,
#   ttl: 300
#
# PDF hot cache (Redis or ETS):
# config :sfera_doc, :pdf_hot_cache,
#   adapter: :redis,
#   ttl: 60
#
# PDF object store (S3 / Azure / FileSystem):
# config :sfera_doc, :pdf_object_store,
#   adapter: SferaDoc.Pdf.ObjectStore.S3,
#   bucket: "my-pdfs"
#
# config :sfera_doc, :chromic_pdf,
#   session_pool: [size: 2, timeout: 10_000]

if config_env() == :test, do: import_config("test.exs")
