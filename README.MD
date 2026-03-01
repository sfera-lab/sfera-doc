<h1 style="color:#7C3AED; font-weight:400; letter-spacing:0.5px;">
  <span style="font-weight:700;">Sfera</span>Doc
</h1>

[![Hex.pm](https://img.shields.io/hexpm/v/sfera_doc.svg)](https://hex.pm/packages/sfera_doc) [![HexDocs](https://img.shields.io/badge/hexdocs-reference-1f6feb)](https://hexdocs.pm/sfera_doc/SferaDoc.html) [![Website](https://img.shields.io/badge/website-sfera--doc-0ea5e9)](https://sfera-lab.github.io/sfera-doc/)

PDF generation library for Elixir. Store versioned [Liquid](https://shopify.github.io/liquid/) templates in your database, render them to PDF via Chrome.

## Features
- **Template storage**: Liquid templates stored with full version history (Ecto, ETS, or Redis)
- **Template parsing**: Powered by [`solid`](https://hex.pm/packages/solid); parsed ASTs are cached in ETS
- **PDF rendering**: HTML rendered by [`chromic_pdf`](https://hex.pm/packages/chromic_pdf) (Chrome-based)
- **PDF storage**: Two-tier: Redis/ETS hot cache + durable object store (S3, Azure Blob, or file system)
- **Variable validation**: Declare required variables per template and get clear errors before rendering

## Installation

```elixir
def deps do
  [
    {:sfera_doc, "~> 0.1.0"},

    # Required if using the Ecto storage backend
    {:ecto_sql, "~> 3.10"},
    {:postgrex, ">= 0.0.0"},  # or :myxql / :ecto_sqlite3

    # Required if using the Redis storage backend
    {:redix, "~> 1.1"},

    # Required for PDF rendering
    {:chromic_pdf, "~> 1.14"},

    # Required if using the S3 PDF object store
    {:ex_aws, "~> 2.5"},
    {:ex_aws_s3, "~> 2.5"},

    # Required if using the Azure Blob PDF object store
    {:azurex, "~> 1.1"}
  ]
end
```

## Setup

### 1. Configure a storage backend

```elixir
# config/config.exs

# Ecto (recommended for production)
config :sfera_doc, :store,
  adapter: SferaDoc.Store.Ecto,
  repo: MyApp.Repo

# Redis
config :sfera_doc, :store, adapter: SferaDoc.Store.Redis
config :sfera_doc, :redis, host: "localhost", port: 6379

# ETS: dev/test only, data is lost on restart
config :sfera_doc, :store, adapter: SferaDoc.Store.ETS
```

### 2. Create the database table (Ecto only)

Create a new mgiration, and copy the example migration from [`priv/migrations/create_sfera_doc_templates.exs`](priv/migrations/create_sfera_doc_templates.exs), then run the migration.


The example includes comments for PostgreSQL-specific parts (the `pgcrypto` extension and the partial unique index). Remove those if you are using MySQL or SQLite.

## Usage

### Create a template

```elixir
{:ok, template} = SferaDoc.create_template(
  "invoice",
  """
  <html>
  <body>
    <h1>Invoice #{{ number }}</h1>
    <p>Bill to: {{ customer_name }}</p>
    <p>Amount due: {{ amount }}</p>
  </body>
  </html>
  """,
  variables_schema: %{
    "required" => ["number", "customer_name", "amount"]
  }
)
```

### Render to PDF

```elixir
{:ok, pdf_binary} = SferaDoc.render("invoice", %{
  "number"        => "INV-0042",
  "customer_name" => "Acme Corp",
  "amount"        => "$1,200.00"
})

File.write!("invoice.pdf", pdf_binary)
```

### Missing variables

If required variables are absent, rendering is short-circuited before any parsing or Chrome calls:

```elixir
{:error, {:missing_variables, ["amount"]}} =
  SferaDoc.render("invoice", %{"number" => "1", "customer_name" => "Acme"})
```

### Template versioning

Every `update_template/3` call creates a new version and activates it. Previous versions are preserved.

```elixir
{:ok, v1} = SferaDoc.create_template("report", "<p>Draft</p>")
{:ok, v2} = SferaDoc.update_template("report", "<p>Final</p>")

# List all versions
{:ok, versions} = SferaDoc.list_versions("report")
# => [%Template{version: 2, is_active: true}, %Template{version: 1, is_active: false}]

# Render a specific version
{:ok, pdf} = SferaDoc.render("report", %{}, version: 1)

# Roll back to a previous version
{:ok, _} = SferaDoc.activate_version("report", 1)
```

### Other operations

```elixir
# Fetch template metadata (no rendering)
{:ok, template} = SferaDoc.get_template("invoice")
{:ok, template} = SferaDoc.get_template("invoice", version: 2)

# List all templates (active version per name)
{:ok, templates} = SferaDoc.list_templates()

# Delete all versions of a template
:ok = SferaDoc.delete_template("invoice")
```

## Configuration Reference

```elixir
# Storage backend (required)
config :sfera_doc, :store,
  adapter: SferaDoc.Store.Ecto,
  repo: MyApp.Repo,
  table_name: "sfera_doc_templates"   # optional, compile-time

# Redis connection (when using Redis adapter)
config :sfera_doc, :redis,
  host: "localhost",
  port: 6379

# Or with a URI:
config :sfera_doc, :redis, "redis://localhost:6379"

# Parsed template AST cache (default: enabled, 300s TTL)
config :sfera_doc, :cache,
  enabled: true,
  ttl: 300

# ChromicPDF options (passed through to ChromicPDF supervisor)
config :sfera_doc, :chromic_pdf,
  session_pool: [size: 2, timeout: 10_000]

# Template engine adapter (defaults to Solid)
config :sfera_doc, :template_engine,
  adapter: SferaDoc.TemplateEngine.Solid

# PDF engine adapter (defaults to ChromicPDF)
config :sfera_doc, :pdf_engine,
  adapter: SferaDoc.PdfEngine.ChromicPDF
```

### PDF hot cache (opt-in)

A fast, ephemeral front-tier cache. Repeat requests with identical variables are
served from Redis or ETS without touching the object store or Chrome.

```elixir
# Redis (distributed, recommended for multi-node)
config :sfera_doc, :pdf_hot_cache,
  adapter: :redis,
  ttl: 60          # seconds

# ETS (single-node, zero external deps)
config :sfera_doc, :pdf_hot_cache,
  adapter: :ets,
  ttl: 300
```

> **Warning:** PDFs can be 100 KB – 10 MB or more. Keep TTLs short and monitor memory.
> For Redis, set `maxmemory-policy allkeys-lru`.

### PDF object store (opt-in)

A durable, persistent tier, the **source of truth** for rendered PDFs. PDFs survive
BEAM restarts. On a cache hit the PDF is returned directly and the hot cache is
populated, avoiding Chrome entirely.

```elixir
# Amazon S3 (requires :ex_aws and :ex_aws_s3)
config :sfera_doc, :pdf_object_store,
  adapter: SferaDoc.Pdf.ObjectStore.S3,
  bucket: "my-pdfs",
  prefix: "sfera_doc/"   # optional

# Azure Blob Storage (requires :azurex)
config :sfera_doc, :pdf_object_store,
  adapter: SferaDoc.Pdf.ObjectStore.Azure,
  container: "my-pdfs"

# azurex credentials (can also be passed inline in the config above)
config :azurex, Azurex.Blob.Config,
  storage_account_name: "mystorageaccount",
  storage_account_key: "base64encodedkey=="

# Local / shared file system (no extra deps)
config :sfera_doc, :pdf_object_store,
  adapter: SferaDoc.Pdf.ObjectStore.FileSystem,
  path: "/var/data/pdfs"
```

Both tiers are fully independent. You can use the object store without a hot cache,
the hot cache without the object store, both together, or neither (generate on every
request, the original behaviour).

## Storage Backends

| Adapter | Use case |
|---|---|
| `SferaDoc.Store.Ecto` | Production: PostgreSQL, MySQL, SQLite |
| `SferaDoc.Store.ETS` | Development and testing only (data lost on restart) |
| `SferaDoc.Store.Redis` | Distributed / Redis-heavy stacks |

## Telemetry

SferaDoc emits the following telemetry events:

| Event | Measurements | Metadata |
|---|---|---|
| `[:sfera_doc, :render, :start]` | `system_time` | `template_name` |
| `[:sfera_doc, :render, :stop]` | `duration` | `template_name` |
| `[:sfera_doc, :render, :exception]` | `duration` | `template_name`, `error` |

 <h1> Made with ❤️ by<span style="font-weight:700; color:#7C3AED; letter-spacing:0.5px;" > Sfera</span>
</h1>



