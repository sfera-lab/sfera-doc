defmodule SferaDoc.Config do
  @moduledoc """
  Configuration accessor for SferaDoc.

  Separates compile-time config (embedded in Ecto schema module attributes)
  from runtime config (read on each call, supports hot reloads in releases).

  ## Compile-time options

  These are read with `Application.compile_env/3` at compilation time:

  - `:store, :table_name`: Ecto table name (default: `"sfera_doc_templates"`)

  ## Runtime options

  These are read with `Application.get_env/3` at runtime:

  - `:store, :adapter`: required, the storage backend module
  - `:store, :repo`: required when using `SferaDoc.Store.Ecto`
  - `:redis`: Redis connection options (host, port, url, etc.)
  - `:cache, :enabled`: whether to cache parsed template ASTs (default: `true`)
  - `:cache, :ttl`: AST cache TTL in seconds (default: `300`)
  - `:pdf_hot_cache, :adapter`: PDF hot-cache backend (`:redis` or `:ets`, default: disabled)
  - `:pdf_hot_cache, :ttl`: hot-cache TTL in seconds (default: `60`)
  - `:pdf_object_store, :adapter`: PDF object-store adapter module (default: disabled)
  - `:chromic_pdf`: options passed directly to `ChromicPDF` (default: `[]`)
  """

  # ---------------------------------------------------------------------------
  # Compile-time
  # ---------------------------------------------------------------------------

  # Must be a module attribute so Application.compile_env is called in the
  # module body, not inside a function (which is not allowed).
  @ecto_table_name Application.compile_env(
                     :sfera_doc,
                     [:store, :table_name],
                     "sfera_doc_templates"
                   )

  @doc """
  Returns the Ecto table name for the templates table.
  Read at compile time: used as a module attribute in `SferaDoc.Store.Ecto.Record`.
  """
  def ecto_table_name, do: @ecto_table_name

  # ---------------------------------------------------------------------------
  # Runtime: store
  # ---------------------------------------------------------------------------

  @doc "Returns the configured store adapter module."
  def store_adapter do
    case Application.get_env(:sfera_doc, :store, [])[:adapter] do
      nil ->
        raise """
        SferaDoc: no store adapter configured.
        Add the following to your config:

            config :sfera_doc, :store,
              adapter: SferaDoc.Store.Ecto,
              repo: MyApp.Repo
        """

      adapter ->
        adapter
    end
  end

  @doc "Returns the Ecto repo module. Raises if not set."
  def ecto_repo do
    case Application.get_env(:sfera_doc, :store, [])[:repo] do
      nil ->
        raise """
        SferaDoc: no Ecto repo configured.
        Add the following to your config:

            config :sfera_doc, :store,
              adapter: SferaDoc.Store.Ecto,
              repo: MyApp.Repo
        """

      repo ->
        repo
    end
  end

  # ---------------------------------------------------------------------------
  # Runtime: Redis
  # ---------------------------------------------------------------------------

  @doc """
  Returns the Redis connection options.
  Accepts a URI string, a `{host, port}` tuple, or a keyword list.
  """
  def redis_config do
    Application.get_env(:sfera_doc, :redis, host: "localhost", port: 6379)
  end

  # ---------------------------------------------------------------------------
  # Runtime: AST cache
  # ---------------------------------------------------------------------------

  @doc "Returns `true` if the parsed-template AST cache is enabled (default: `true`)."
  def cache_enabled? do
    Application.get_env(:sfera_doc, :cache, []) |> Keyword.get(:enabled, true)
  end

  @doc "Returns the AST cache TTL in seconds (default: `300`)."
  def cache_ttl do
    Application.get_env(:sfera_doc, :cache, []) |> Keyword.get(:ttl, 300)
  end

  # ---------------------------------------------------------------------------
  # Runtime: PDF hot cache
  # ---------------------------------------------------------------------------

  @doc "Returns the PDF hot-cache adapter: `:redis`, `:ets`, or `nil` (disabled)."
  def pdf_hot_cache_adapter do
    Application.get_env(:sfera_doc, :pdf_hot_cache, [])[:adapter]
  end

  @doc "Returns the PDF hot-cache TTL in seconds (default: `60`)."
  def pdf_hot_cache_ttl do
    Application.get_env(:sfera_doc, :pdf_hot_cache, []) |> Keyword.get(:ttl, 60)
  end

  # ---------------------------------------------------------------------------
  # Runtime: PDF object store
  # ---------------------------------------------------------------------------

  @doc "Returns the PDF object-store adapter module, or `nil` if not configured."
  def pdf_object_store_adapter do
    Application.get_env(:sfera_doc, :pdf_object_store, [])[:adapter]
  end

  @doc "Returns the PDF object-store options keyword list."
  def pdf_object_store_opts do
    Application.get_env(:sfera_doc, :pdf_object_store, [])
  end

  # ---------------------------------------------------------------------------
  # Runtime: ChromicPDF
  # ---------------------------------------------------------------------------

  @doc "Returns ChromicPDF supervisor options, passed through from config."
  def chromic_pdf_opts do
    Application.get_env(:sfera_doc, :chromic_pdf, [])
  end
end
