defmodule SferaDoc do
  @moduledoc """
  PDF generation library with versioned Liquid templates stored in a database.

  SferaDoc combines three things:

  1. **Template storage**: Liquid templates are stored in your database (or ETS/Redis)
     with automatic versioning. Each `update_template/3` call creates a new version
     while keeping the full history.

  2. **Template parsing**: Templates are parsed with the [`solid`](https://hex.pm/packages/solid)
     Liquid template engine. Parsed ASTs are cached in ETS to avoid repeated parsing.

  3. **PDF rendering**: Rendered HTML is passed to
     [`chromic_pdf`](https://hex.pm/packages/chromic_pdf) (Chrome-based) to produce
     a PDF binary.

  ## Quick Start

      # 1. Configure a storage backend
      config :sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: MyApp.Repo

      # 2. Add a migration
      defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
        use SferaDoc.Store.Ecto.Migration
      end

      # 3. Create a template
      {:ok, template} = SferaDoc.create_template(
        "invoice",
        "<h1>Invoice for {{ customer_name }}</h1><p>Amount: {{ amount }}</p>",
        variables_schema: %{"required" => ["customer_name", "amount"]}
      )

      # 4. Render to PDF
      {:ok, pdf_binary} = SferaDoc.render("invoice", %{
        "customer_name" => "Acme Corp",
        "amount" => "$1,200.00"
      })

      # Save to file
      File.write!("invoice.pdf", pdf_binary)

  ## Storage Backends

  | Adapter | Use case |
  |---|---|
  | `SferaDoc.Store.Ecto` | Production: PostgreSQL, MySQL, SQLite |
  | `SferaDoc.Store.ETS` | Development and testing only |
  | `SferaDoc.Store.Redis` | Distributed / Redis-heavy stacks |

  ## Template Versioning

  Every call to `update_template/3` creates a new version and makes it active.
  Previous versions are preserved and can be restored with `activate_version/2`.

      {:ok, v1} = SferaDoc.create_template("invoice", "<h1>v1</h1>")
      {:ok, v2} = SferaDoc.update_template("invoice", "<h1>v2</h1>")

      SferaDoc.list_versions("invoice")
      # => {:ok, [%Template{version: 2, is_active: true}, %Template{version: 1, is_active: false}]}

      SferaDoc.activate_version("invoice", 1)   # roll back to v1

  ## PDF Cache Warning

  Rendering a PDF involves a round-trip to a Chrome process and can be slow.
  An optional Redis-backed cache for rendered PDFs is available:

      config :sfera_doc, :pdf_cache,
        enabled: true,
        ttl: 60

  > #### Memory Warning {: .warning}
  >
  > PDFs can be 100 KB – 10 MB or more. Only enable this cache with an
  > explicit TTL and a Redis `maxmemory-policy`. ETS is intentionally not
  > supported for PDF caching.
  """

  alias SferaDoc.{Store, Renderer, Template}

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  @doc """
  Renders the active version of a template to a PDF binary.

  ## Options

  - `:version`: render a specific version instead of the currently active one
  - `:chromic_pdf`: extra options forwarded to `ChromicPDF.print_to_pdf/2`

  ## Returns

  - `{:ok, pdf_binary}` on success
  - `{:error, :not_found}` if the template does not exist
  - `{:error, {:missing_variables, [String.t()]}}` if required variables are absent
  - `{:error, {:template_parse_error, error}}` if the Liquid template has syntax errors
  - `{:error, {:template_render_error, errors, partial_html}}` on render-time errors
  - `{:error, {:chromic_pdf_error, reason}}` on PDF generation failure

  ## Examples

      {:ok, pdf} = SferaDoc.render("invoice", %{"name" => "Alice"})
      {:ok, pdf} = SferaDoc.render("invoice", %{"name" => "Alice"}, version: 2)
  """
  @spec render(String.t(), map(), keyword()) :: {:ok, binary()} | {:error, any()}
  def render(name, assigns, opts \\ []), do: Renderer.render(name, assigns, opts)

  # ---------------------------------------------------------------------------
  # Template management
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new template (version 1) or adds version 1 if the name is new.

  Use `update_template/3` to add subsequent versions.

  ## Options

  - `:variables_schema`: map with `"required"` and/or `"optional"` lists:
    `%{"required" => ["name"], "optional" => ["footer"]}`

  ## Example

      {:ok, template} = SferaDoc.create_template(
        "welcome_email",
        "<p>Hello {{ name }}!</p>",
        variables_schema: %{"required" => ["name"]}
      )
  """
  @spec create_template(String.t(), String.t(), keyword()) ::
          {:ok, Template.t()} | {:error, any()}
  def create_template(name, body, opts \\ []) do
    Store.put(%Template{
      name: name,
      body: body,
      variables_schema: Keyword.get(opts, :variables_schema)
    })
  end

  @doc """
  Creates a new version of an existing template.

  The new version is immediately set as active. The previous version is
  preserved and can be restored with `activate_version/2`.

  Accepts the same options as `create_template/3`.
  """
  @spec update_template(String.t(), String.t(), keyword()) ::
          {:ok, Template.t()} | {:error, any()}
  def update_template(name, new_body, opts \\ []) do
    Store.put(%Template{
      name: name,
      body: new_body,
      variables_schema: Keyword.get(opts, :variables_schema)
    })
  end

  @doc """
  Returns the active template for `name`, or a specific version.

  ## Options

  - `:version`: return a specific version number instead of the active one

  ## Examples

      {:ok, template} = SferaDoc.get_template("invoice")
      {:ok, v2} = SferaDoc.get_template("invoice", version: 2)
  """
  @spec get_template(String.t(), keyword()) :: {:ok, Template.t()} | {:error, any()}
  def get_template(name, opts \\ []) do
    case Keyword.get(opts, :version) do
      nil -> Store.get(name)
      version -> Store.get_version(name, version)
    end
  end

  @doc """
  Returns a list of all templates (latest active version per name).
  """
  @spec list_templates() :: {:ok, [Template.t()]} | {:error, any()}
  def list_templates, do: Store.list()

  @doc """
  Returns all versions of a template, ordered by version descending.
  """
  @spec list_versions(String.t()) :: {:ok, [Template.t()]} | {:error, any()}
  def list_versions(name), do: Store.list_versions(name)

  @doc """
  Activates a specific version of a template, deactivating the current one.

  Useful for rolling back to a previous version.

  ## Example

      {:ok, template} = SferaDoc.activate_version("invoice", 1)
  """
  @spec activate_version(String.t(), pos_integer()) ::
          {:ok, Template.t()} | {:error, any()}
  def activate_version(name, version), do: Store.activate_version(name, version)

  @doc """
  Deletes all versions of a template by name.

  This operation is irreversible.
  """
  @spec delete_template(String.t()) :: :ok | {:error, any()}
  def delete_template(name), do: Store.delete(name)
end
