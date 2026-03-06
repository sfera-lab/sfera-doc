defmodule SferaDoc do
  @moduledoc """
  PDF generation with versioned Liquid templates.

  SferaDoc combines:
  - **Storage**: Templates in Ecto/ETS/Redis with automatic versioning
  - **Parsing**: Liquid templates via [`solid`](https://hex.pm/packages/solid) (default, pluggable), cached in ETS
  - **Rendering**: HTML to PDF via [`chromic_pdf`](https://hex.pm/packages/chromic_pdf) (default, pluggable)
  - **Cache**: Optional fast in-memory PDF cache (Redis/ETS)
  - **Object Store**: Optional durable PDF storage (S3/Azure/FileSystem)

  ## Quick Start

      # 1. Configure storage
      config :sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: MyApp.Repo

      # 2. Add migration
      defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
        use SferaDoc.Store.Ecto.Migration
      end

      # 3. Create template
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

      File.write!("invoice.pdf", pdf_binary)

  ## Storage Backends

  Storage backends persist **template source code** and its metadata (name, version, variables_schema).
  This is separate from PDF storage  templates are the input, PDFs are the output.

  | Adapter | Use case |
  |---|---|
  | `SferaDoc.Store.Ecto` | Production (PostgreSQL, MySQL, SQLite) |
  | `SferaDoc.Store.ETS` | Development/testing only |
  | `SferaDoc.Store.Redis` | Distributed systems |

  ## Two-Tier PDF Storage

  SferaDoc uses a two-tier storage system for rendered PDFs:

  1. **Cache** (fast, in-memory) - First lookup, short TTL
  2. **Object store** (durable storage) - Second lookup, survives restarts

  ### Cache

  Fast in-memory cache. Supports Redis or ETS. Disabled by default.

      # Redis (multi-node, production)
      config :sfera_doc, :pdf_hot_cache,
        adapter: :redis,
        ttl: 60

      # ETS (single-node, development)
      config :sfera_doc, :pdf_hot_cache,
        adapter: :ets,
        ttl: 300

  Override Redis connection (reuses `:redis` config by default):

      config :sfera_doc, :pdf_hot_cache,
        adapter: :redis,
        ttl: 60,
        redis: [host: "cache.example.com", port: 6379]

  ### Object Store

  Durable storage for rendered PDFs. Available adapters:

  | Adapter | Storage |
  |---|---|
  | `SferaDoc.Pdf.ObjectStore.S3` | Amazon S3 / S3-compatible |
  | `SferaDoc.Pdf.ObjectStore.Azure` | Azure Blob Storage |
  | `SferaDoc.Pdf.ObjectStore.FileSystem` | Local/shared filesystem |

  Example S3 configuration:

      config :sfera_doc, :pdf_object_store,
        adapter: SferaDoc.Pdf.ObjectStore.S3,
        bucket: "my-pdfs",
        region: "us-east-1"

  For custom object store adapters, see **Pluggable Engines** below.

  > #### Warning {: .warning}
  >
  > PDFs can be 100 KB – 10 MB+. For Redis cache, set explicit TTL
  > and `maxmemory-policy allkeys-lru` to prevent memory issues.

  ## Versioning

  Each update creates a new version. Previous versions are preserved.

      iex> SferaDoc.create_template("template_name", "<h1>v1</h1>")
      {:ok,
       %SferaDoc.Template{
         id: "c41ee418-e479-4751-8331-b55af0f8ef97",
         name: "template_name",
         body: "<h1>v1</h1>",
         version: 1,
         is_active: true,
         variables_schema: nil,
         inserted_at: ~U[2026-03-06 20:26:41Z],
         updated_at: ~U[2026-03-06 20:26:41Z]
       }}

      iex> SferaDoc.update_template("template_name", "<h1>v2</h1>")
      {:ok,
       %SferaDoc.Template{
         id: "942ba9af-a542-43e8-9b71-1313e2c551ef",
         name: "template_name",
         body: "<h1>v2</h1>",
         version: 2,
         is_active: true,
         variables_schema: nil,
         inserted_at: ~U[2026-03-06 20:28:25Z],
         updated_at: ~U[2026-03-06 20:28:25Z]
       }}

      iex> SferaDoc.list_versions("template_name")
      {:ok,
       [
         %SferaDoc.Template{
           id: "942ba9af-a542-43e8-9b71-1313e2c551ef",
           name: "template_name",
           body: "<h1>v2</h1>",
           version: 2,
           is_active: true,
           variables_schema: nil,
           inserted_at: ~U[2026-03-06 20:28:25Z],
           updated_at: ~U[2026-03-06 20:28:25Z]
         },
         %SferaDoc.Template{
           id: "c41ee418-e479-4751-8331-b55af0f8ef97",
           name: "template_name",
           body: "<h1>v1</h1>",
           version: 1,
           is_active: false,
           variables_schema: nil,
           inserted_at: ~U[2026-03-06 20:26:41Z],
           updated_at: ~U[2026-03-06 20:26:41Z]
         }
       ]}

      iex> SferaDoc.activate_version("template_name", 1)  # rollback
      {:ok,
       %SferaDoc.Template{
         id: "c41ee418-e479-4751-8331-b55af0f8ef97",
         name: "template_name",
         body: "<h1>v1</h1>",
         version: 1,
         is_active: true,
         variables_schema: nil,
         inserted_at: ~U[2026-03-06 20:26:41Z],
         updated_at: ~U[2026-03-06 20:31:45Z]
       }}

      iex> SferaDoc.list_versions("template_name")
      {:ok,
       [
         %SferaDoc.Template{
           id: "942ba9af-a542-43e8-9b71-1313e2c551ef",
           name: "template_name",
           body: "<h1>v2</h1>",
           version: 2,
           is_active: false,
           variables_schema: nil,
           inserted_at: ~U[2026-03-06 20:28:25Z],
           updated_at: ~U[2026-03-06 20:28:25Z]
         },
         %SferaDoc.Template{
           id: "c41ee418-e479-4751-8331-b55af0f8ef97",
           name: "template_name",
           body: "<h1>v1</h1>",
           version: 1,
           is_active: true,
           variables_schema: nil,
           inserted_at: ~U[2026-03-06 20:26:41Z],
           updated_at: ~U[2026-03-06 20:31:45Z]
         }
       ]}



  ## Pluggable Engines

  Storage backends, template engines, and PDF engines are all swappable via behavior adapters.

  **Storage Backend** - Implement `SferaDoc.Store.Adapter`:

      defmodule MyApp.MongoAdapter do
        @behaviour SferaDoc.Store.Adapter

        def worker_spec, do: nil  # Assuming Mongo supervised elsewhere

        def get(name), do: # Fetch active template by name
        def get_version(name, version), do: # Fetch specific version
        def put(template), do: # Insert/update with versioning
        def list(), do: # All templates (active only)
        def list_versions(name), do: # All versions for name
        def activate_version(name, version), do: # Make version active
        def delete(name), do: # Delete all versions
      end

      config :sfera_doc, :store,
        adapter: MyApp.MongoAdapter

  **Template Engine** - Implement `SferaDoc.TemplateEngine.Adapter`:

      defmodule MyApp.CustomTemplateEngine do
        @behaviour SferaDoc.TemplateEngine.Adapter

        def parse(template), do: {:ok, Mustache.compile(template)}
        def render(ast, vars), do: {:ok, Mustache.render(ast, vars)}
      end

      config :sfera_doc, :template_engine,
        adapter: MyApp.CustomTemplateEngine

  **PDF Engine** - Implement `SferaDoc.PdfEngine.Adapter`:

      defmodule MyApp.CustomPdfEngine do
        @behaviour SferaDoc.PdfEngine.Adapter

        def render(html, _opts) do
          # Shell out to WeasyPrint, wkhtmltopdf, etc.
          {:ok, pdf_binary}
        end
      end

      config :sfera_doc, :pdf_engine,
        adapter: MyApp.CustomPdfEngine

  **PDF Object Store** - Implement `SferaDoc.Pdf.ObjectStore.Adapter`:

      defmodule MyApp.GCSAdapter do
        @behaviour SferaDoc.Pdf.ObjectStore.Adapter

        def worker_spec, do: nil  # HTTP client, no supervision needed

        def get(name, version, hash) do
          # Fetch from Google Cloud Storage
          {:ok, pdf_binary}  # or :miss
        end

        def put(name, version, hash, binary) do
          # Upload to GCS
          :ok
        end
      end

      config :sfera_doc, :pdf_object_store,
        adapter: MyApp.GCSAdapter
  """

  alias SferaDoc.{Store, Renderer, Template}

  # ---------------------------------------------------------------------------
  # Rendering
  # ---------------------------------------------------------------------------

  @doc """
  Renders the active version of a template to a PDF binary.

  ## Options

  - `:version`: render a specific version instead of the currently active one
  - `:chromic_pdf`: extra options forwarded to the PDF engine (e.g. to `ChromicPDF.print_to_pdf/2`)

  ## Returns

  - `{:ok, pdf_binary}` on success
  - `{:error, :not_found}` if the template does not exist
  - `{:error, {:missing_variables, [String.t()]}}` if required variables are absent
  - `{:error, {:template_parse_error, error}}` if the Liquid template has syntax errors
  - `{:error, {:template_render_error, errors, partial_html}}` on render-time errors
  - `{:error, {:chromic_pdf_error, reason}}` on PDF generation failure

  ## Examples

      {:ok, pdf} = SferaDoc.render(
               "welcome_email",
               %{"name" => "Alice"}
             )
  """
  @spec render(String.t(), map(), keyword()) :: {:ok, binary()} | {:error, any()}
  def render(name, assigns, opts \\ []), do: Renderer.render(name, assigns, opts)

  # ---------------------------------------------------------------------------
  # Template management
  # ---------------------------------------------------------------------------

  @doc """
  Creates a new template with version 1 if new, or adds version (<latest_version>+1) if a template with the same name exists.

  Use `update_template/3` to add subsequent versions.

  ## Options

  - `:variables_schema`: map with `"required"` and/or `"optional"` lists:
    `%{"required" => ["name"], "optional" => ["footer"]}`

  ## Example

      {:ok,
       %SferaDoc.Template{
         id: "cd940533-52ee-4b6a-bb14-902f21d234b6",
         name: "welcome_email",
         body: "<p>Hello {{ name }}!</p>",
         version: 1,
         is_active: true,
         variables_schema: %{"required" => ["name"]},
         inserted_at: ~U[2026-03-06 19:31:09Z],
         updated_at: ~U[2026-03-06 19:31:09Z]
       }} = SferaDoc.create_template(
               "welcome_email",
               "<p>Hello {{ name }}!</p>",
               variables_schema: %{"required" => ["name"]}
             )
  """
  @spec create_template(String.t(), String.t(), keyword()) ::
          {:ok, Template.t()} | {:error, any()}
  def create_template(name, body, opts \\ []) when is_binary(name) and is_binary(body) do
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
