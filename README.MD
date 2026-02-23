# SferaDoc

PDF generation library for Elixir. Store versioned [Liquid](https://shopify.github.io/liquid/) templates in your database, render them to PDF via Chrome.

- **Template storage** — Liquid templates stored with full version history (Ecto, ETS, or Redis)
- **Template parsing** — Powered by [`solid`](https://hex.pm/packages/solid); parsed ASTs are cached in ETS
- **PDF rendering** — HTML rendered by [`chromic_pdf`](https://hex.pm/packages/chromic_pdf) (Chrome-based)
- **Variable validation** — Declare required variables per template and get clear errors before rendering

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
    {:chromic_pdf, "~> 1.14"}
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

# ETS — dev/test only, data is lost on restart
config :sfera_doc, :store, adapter: SferaDoc.Store.ETS
```

### 2. Add to your supervision tree

SferaDoc starts its own supervisor (including a Chrome process pool). Add it to your application:

```elixir
def start(_type, _args) do
  children = [
    MyApp.Repo,
    # other children...
  ]
  Supervisor.start_link(children, strategy: :one_for_one)
end
```

SferaDoc's supervisor is started automatically via its OTP application callback — no manual entry required.

### 3. Create the database table (Ecto only)

Generate a migration:

```
mix sfera_doc.ecto.setup
mix ecto.migrate
```

Or add the migration manually:

```elixir
defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
  use SferaDoc.Store.Ecto.Migration
end
```

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
```

### PDF output cache (opt-in)

```elixir
config :sfera_doc, :pdf_cache,
  enabled: true,
  ttl: 60
```

> **Warning:** PDFs can be 100 KB – 10 MB or more. Only enable the PDF cache when:
> - Your PDFs are small and frequently re-requested with identical variables
> - Redis `maxmemory-policy` is set to `allkeys-lru`
> - An explicit TTL is configured
>
> Requires the Redis storage adapter. ETS is intentionally not supported for PDF caching.

## Storage Backends

| Adapter | Use case |
|---|---|
| `SferaDoc.Store.Ecto` | Production — PostgreSQL, MySQL, SQLite |
| `SferaDoc.Store.ETS` | Development and testing only (data lost on restart) |
| `SferaDoc.Store.Redis` | Distributed / Redis-heavy stacks |

## Telemetry

SferaDoc emits the following telemetry events:

| Event | Measurements | Metadata |
|---|---|---|
| `[:sfera_doc, :render, :start]` | `system_time` | `template_name` |
| `[:sfera_doc, :render, :stop]` | `duration` | `template_name` |
| `[:sfera_doc, :render, :exception]` | `duration` | `template_name`, `error` |

## License

MIT
