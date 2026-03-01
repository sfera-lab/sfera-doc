---
title: Template Versioning
description: Every template update creates a new version. Roll back to any previous version at any time.
order: 4
---

## How Versioning Works

Every call to `SferaDoc.update_template/3` creates a new version and immediately makes it the **active** version. Previous versions are preserved indefinitely.

At render time, SferaDoc uses the active version unless you explicitly request another.

## Creating and Updating Templates

```elixir
# Creates version 1
{:ok, v1} = SferaDoc.create_template(
  "invoice",
  "<h1>Invoice v1 for {{ name }}</h1>",
  variables_schema: %{"required" => ["name"]}
)

# Creates version 2 and activates it
{:ok, v2} = SferaDoc.update_template(
  "invoice",
  "<h1>Invoice v2 for {{ name }}</h1><p>New layout</p>"
)
```

## Listing Versions

```elixir
{:ok, versions} = SferaDoc.list_versions("invoice")
# => [
#      %Template{version: 2, is_active: true,  ...},
#      %Template{version: 1, is_active: false, ...}
#    ]
```

Versions are returned in descending order (newest first).

## Fetching a Specific Version

```elixir
# Get the active version
{:ok, template} = SferaDoc.get_template("invoice")

# Get a specific version
{:ok, v1} = SferaDoc.get_template("invoice", version: 1)
```

## Rolling Back

Activate any previous version to make it the current one:

```elixir
{:ok, _} = SferaDoc.activate_version("invoice", 1)

# Now version 1 is active again
{:ok, versions} = SferaDoc.list_versions("invoice")
# => [
#      %Template{version: 2, is_active: false, ...},
#      %Template{version: 1, is_active: true,  ...}
#    ]
```

## Rendering a Specific Version

You can render any version without changing the active version:

```elixir
# Renders the active version
{:ok, pdf} = SferaDoc.render("invoice", %{"name" => "Alice"})

# Renders version 1 regardless of which is active
{:ok, pdf} = SferaDoc.render("invoice", %{"name" => "Alice"}, version: 1)
```

## Deleting a Template

Deletes all versions of a template. **Irreversible.**

```elixir
:ok = SferaDoc.delete_template("invoice")
```

## Variable Schema

Each version can have its own `variables_schema`, declaring which variables are required and which are optional:

```elixir
SferaDoc.create_template(
  "receipt",
  "...",
  variables_schema: %{
    "required" => ["amount", "customer_name"],
    "optional" => ["tax_rate", "footer_note"]
  }
)
```

If a render call is missing required variables, SferaDoc returns:

```elixir
{:error, {:missing_variables, ["amount"]}}
```
