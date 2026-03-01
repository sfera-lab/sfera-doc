---
title: Getting Started
description: Install SferaDoc, configure a storage backend, and generate your first PDF.
order: 1
---

## Requirements

- Elixir ~> 1.15
- A supported storage backend (Ecto, ETS, or Redis)
- Chrome / Chromium installed for PDF generation via ChromicPDF

## Installation

Add `:sfera_doc` and the optional dependencies you need to `mix.exs`:

```elixir
def deps do
  [
    {:sfera_doc, "~> 0.1"},

    # Storage — pick one or more
    {:ecto_sql, "~> 3.10"},      # PostgreSQL / SQLite
    {:postgrex, ">= 0.0.0"},    # PostgreSQL driver
    # {:ecto_sqlite3, ">= 0.0.0"}, # SQLite driver

    # PDF engine
    {:chromic_pdf, "~> 1.14"},
  ]
end
```

Then fetch:

```sh
mix deps.get
```

## Configuration

Configure the store adapter in `config/config.exs` (or your environment file):

```elixir
config :sfera_doc, :store,
  adapter: SferaDoc.Store.Ecto,
  repo: MyApp.Repo
```

## Database Migration

Use the built-in migration module to create the templates table:

```elixir
defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
  use SferaDoc.Store.Ecto.Migration
end
```

Run the migration:

```sh
mix ecto.migrate
```

## Supervision

Add SferaDoc to your application's supervision tree:

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      MyApp.Repo,
      SferaDoc.Supervisor,
      # ...
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end
end
```

## Quick Start

```elixir
# 1. Create a template
{:ok, _} = SferaDoc.create_template(
  "invoice",
  "<h1>Invoice for {{ customer_name }}</h1><p>Amount: {{ amount }}</p>",
  variables_schema: %{
    "required" => ["customer_name", "amount"]
  }
)

# 2. Render to PDF
{:ok, pdf} = SferaDoc.render("invoice", %{
  "customer_name" => "Acme Corp",
  "amount" => "$1,200.00"
})

# 3. Save to disk
File.write!("invoice.pdf", pdf)
```

## Next Steps

- [Configuration](/docs/configuration) — full list of config options
- [Store Adapters](/docs/store-adapters) — Ecto, ETS, and Redis backends
- [Template Versioning](/docs/template-versioning) — version history and rollback
- [PDF Caching](/docs/pdf-caching) — hot cache and object store
