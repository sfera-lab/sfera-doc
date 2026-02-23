import Config

config :sfera_doc, :store, adapter: SferaDoc.Store.ETS
config :sfera_doc, :cache, enabled: false
config :sfera_doc, :chromic_pdf, disabled: true
