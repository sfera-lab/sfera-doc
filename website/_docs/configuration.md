---
title: Configuration
description: Complete reference for all SferaDoc configuration options.
order: 2
---

All options are set via `Application.put_env/3` / `config :sfera_doc, ...` and are read at runtime (unless noted as compile-time).

## Store

```elixir
config :sfera_doc, :store,
  adapter: SferaDoc.Store.Ecto,   # required — see Store Adapters
  repo: MyApp.Repo,               # required when using Ecto
  table_name: "sfera_doc_templates"  # compile-time, default shown
```

`table_name` is a **compile-time** option read with `Application.compile_env/3`. It must be set before compilation and cannot be changed at runtime.

## Template AST Cache

Parsed Liquid ASTs are cached in ETS to avoid re-parsing templates on every render.

```elixir
config :sfera_doc, :cache,
  enabled: true,   # default: true
  ttl: 300         # seconds, default: 300
```

## Redis Connection

Required when using the Redis store adapter or the Redis PDF hot cache.

```elixir
# As a URI
config :sfera_doc, :redis, "redis://localhost:6379/0"

# As a keyword list
config :sfera_doc, :redis,
  host: "localhost",
  port: 6379
```

## PDF Hot Cache

An optional ephemeral cache for rendered PDF binaries. Backed by Redis or ETS.

```elixir
config :sfera_doc, :pdf_hot_cache,
  adapter: :redis,  # :redis or :ets
  ttl: 60           # seconds, default: 60
```

> **Warning:** PDFs can be 100 KB – 10 MB or more. When using `:ets`, set an
> appropriate `ttl` and ensure your VM has sufficient memory. When using `:redis`,
> configure a `maxmemory-policy` (e.g. `allkeys-lru`) on your Redis instance.

## PDF Object Store

An optional durable store for rendered PDFs, independent of the hot cache.

```elixir
# Amazon S3
config :sfera_doc, :pdf_object_store,
  adapter: SferaDoc.PdfEngine.ObjectStore.S3,
  bucket: "my-pdf-bucket",
  prefix: "pdfs/"

# Azure Blob Storage
config :sfera_doc, :pdf_object_store,
  adapter: SferaDoc.PdfEngine.ObjectStore.Azure,
  container: "pdfs"

# Local filesystem
config :sfera_doc, :pdf_object_store,
  adapter: SferaDoc.PdfEngine.ObjectStore.FileSystem,
  path: "/var/app/pdfs"
```

## ChromicPDF

Options forwarded directly to the `ChromicPDF` supervisor and `print_to_pdf/2`.

```elixir
config :sfera_doc, :chromic_pdf,
  # Disable when Chrome is unavailable (e.g. in tests)
  disabled: false,
  # Any other ChromicPDF options...
  no_sandbox: true
```

## Pluggable Adapters

Override the default template engine or PDF engine:

```elixir
config :sfera_doc, :template_engine,
  adapter: MyApp.CustomTemplateEngine   # default: SferaDoc.TemplateEngine.Solid

config :sfera_doc, :pdf_engine,
  adapter: MyApp.CustomPdfEngine        # default: SferaDoc.PdfEngine.ChromicPDF
```

See [Custom Adapters](/docs/custom-adapters) for details.

## Summary Table

| Key | Type | Default | Notes |
|-----|------|---------|-------|
| `:store, :adapter` | module | — | Required |
| `:store, :repo` | module | — | Required for Ecto |
| `:store, :table_name` | string | `"sfera_doc_templates"` | Compile-time |
| `:cache, :enabled` | boolean | `true` | AST cache |
| `:cache, :ttl` | integer | `300` | Seconds |
| `:redis` | keyword/string | `[host: "localhost", port: 6379]` | |
| `:pdf_hot_cache, :adapter` | `:redis` \| `:ets` | disabled | |
| `:pdf_hot_cache, :ttl` | integer | `60` | Seconds |
| `:pdf_object_store, :adapter` | module | disabled | |
| `:chromic_pdf` | keyword | `[]` | Passed to ChromicPDF |
| `:template_engine, :adapter` | module | `SferaDoc.TemplateEngine.Solid` | |
| `:pdf_engine, :adapter` | module | `SferaDoc.PdfEngine.ChromicPDF` | |
