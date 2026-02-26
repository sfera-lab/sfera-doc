---
title: PDF Caching
description: Speed up repeated renders with a hot cache and persist PDFs to durable object storage.
order: 5
---

Generating a PDF involves a round-trip to a Chrome process and can take hundreds of milliseconds. SferaDoc provides two independent, opt-in caching layers.

## Render Pipeline

On each `SferaDoc.render/3` call:

1. **Hot cache** — check Redis/ETS for a cached PDF binary → return if found
2. **Object store** — check durable storage (S3/Azure/FileSystem) → return if found (and backfill hot cache)
3. **Generate** — render the template to HTML, convert to PDF via ChromicPDF, persist to both stores

Both layers are optional and independent of each other.

---

## Hot Cache

Ephemeral cache for fast repeated reads. Backed by Redis or ETS.

### Redis Hot Cache

```elixir
config :sfera_doc, :pdf_hot_cache,
  adapter: :redis,
  ttl: 60   # seconds

config :sfera_doc, :redis,
  host: "localhost",
  port: 6379
```

### ETS Hot Cache

```elixir
config :sfera_doc, :pdf_hot_cache,
  adapter: :ets,
  ttl: 60   # seconds
```

> **Memory warning:** PDFs can be 100 KB – 10 MB or more. Only enable this cache
> with an explicit TTL. For Redis, configure a `maxmemory-policy` (e.g.
> `allkeys-lru`). For ETS, ensure your BEAM VM has enough memory.

---

## Object Store

Durable PDF storage, surviving restarts and deployments. Three adapters are included.

### Amazon S3

Requires `ex_aws` and `ex_aws_s3`:

```elixir
{:ex_aws, "~> 2.5"},
{:ex_aws_s3, "~> 2.5"},
```

```elixir
config :sfera_doc, :pdf_object_store,
  adapter: SferaDoc.PdfEngine.ObjectStore.S3,
  bucket: "my-pdf-bucket",
  prefix: "pdfs/"   # optional key prefix
```

AWS credentials are read from the standard ExAws sources (environment variables, instance profile, etc.).

### Azure Blob Storage

Requires `azurex`:

```elixir
{:azurex, "~> 1.1"},
```

```elixir
config :sfera_doc, :pdf_object_store,
  adapter: SferaDoc.PdfEngine.ObjectStore.Azure,
  container: "pdfs"
```

### Local Filesystem

No extra dependencies:

```elixir
config :sfera_doc, :pdf_object_store,
  adapter: SferaDoc.PdfEngine.ObjectStore.FileSystem,
  path: "/var/app/pdfs"
```

### Custom Object Store Adapter

Implement the `SferaDoc.PdfEngine.ObjectStore.Adapter` behaviour:

```elixir
defmodule MyApp.CustomObjectStore do
  @behaviour SferaDoc.PdfEngine.ObjectStore.Adapter

  @impl true
  def get(key), do: ...       # {:ok, binary} | {:error, :not_found} | {:error, term}

  @impl true
  def put(key, binary), do: ...  # :ok | {:error, term}
end
```

---

## Using Both Layers

Hot cache and object store can be active simultaneously:

```elixir
config :sfera_doc, :pdf_hot_cache,
  adapter: :redis,
  ttl: 300

config :sfera_doc, :pdf_object_store,
  adapter: SferaDoc.PdfEngine.ObjectStore.S3,
  bucket: "my-pdf-bucket"
```

The pipeline will:
1. Return from Redis if present (fastest)
2. Return from S3 if present (and backfill Redis)
3. Generate fresh, write to S3, write to Redis
