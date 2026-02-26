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
#
# Template engine (defaults to Solid):
# config :sfera_doc, :template_engine,
#   adapter: SferaDoc.TemplateEngine.Solid
#
# PDF engine (defaults to ChromicPDF):
# config :sfera_doc, :pdf_engine,
#   adapter: SferaDoc.PdfEngine.ChromicPDF

cond do
  config_env() == :test -> import_config("test.exs")
  true -> :ok
end
