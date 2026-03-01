---
title: Store Adapters
description: Choose and configure where SferaDoc stores your Liquid templates.
order: 3
---

SferaDoc stores templates through an adapter behaviour. Three adapters are included.

## Ecto (recommended for production)

Stores templates in a relational database (PostgreSQL, SQLite) via Ecto.

### Setup

Add dependencies:

```elixir
{:ecto_sql, "~> 3.10"},
{:postgrex, ">= 0.0.0"},   # or {:ecto_sqlite3, ">= 0.0.0"} for SQLite
```

Configure:

```elixir
config :sfera_doc, :store,
  adapter: SferaDoc.Store.Ecto,
  repo: MyApp.Repo
```

Create the migration:

```elixir
defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
  use SferaDoc.Store.Ecto.Migration
end
```

```sh
mix ecto.migrate
```

### Custom Table Name

The table name defaults to `"sfera_doc_templates"`. Override it at compile time:

```elixir
# config/config.exs  (before compilation)
config :sfera_doc, :store, table_name: "pdf_templates"
```

This is a **compile-time** option and must be set before the application is compiled.

---

## ETS

Stores templates in an in-process ETS table. Fast, no external dependencies, but **non-persistent** — data is lost on process restart.

Best for development and testing.

### Setup

No extra dependencies. Configure:

```elixir
config :sfera_doc, :store,
  adapter: SferaDoc.Store.ETS
```

### Resetting in Tests

```elixir
SferaDoc.Store.ETS.reset()
```

This goes through the GenServer that owns the `:protected` ETS table, so it is safe to call from test processes.

---

## Redis

Stores templates in Redis. Useful for distributed setups or Redis-heavy stacks.

### Setup

Add dependency:

```elixir
{:redix, "~> 1.1"}
```

Configure:

```elixir
config :sfera_doc, :store,
  adapter: SferaDoc.Store.Redis

config :sfera_doc, :redis,
  host: "localhost",
  port: 6379
```

---

## Custom Adapter

Implement the `SferaDoc.Store.Adapter` behaviour to use any other storage system:

```elixir
defmodule MyApp.CustomStore do
  @behaviour SferaDoc.Store.Adapter

  @impl true
  def put(template), do: ...

  @impl true
  def get(name), do: ...

  @impl true
  def get_version(name, version), do: ...

  @impl true
  def list(), do: ...

  @impl true
  def list_versions(name), do: ...

  @impl true
  def activate_version(name, version), do: ...

  @impl true
  def delete(name), do: ...
end
```

Then configure:

```elixir
config :sfera_doc, :store,
  adapter: MyApp.CustomStore
```
