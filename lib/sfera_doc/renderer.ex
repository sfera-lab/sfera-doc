defmodule SferaDoc.Renderer do
  @moduledoc false
  # Orchestrates the full rendering pipeline:
  #   fetch → validate vars → hot cache? → object store? → parse → render HTML → render PDF → store

  require Logger

  alias SferaDoc.{Store, Template}
  alias SferaDoc.Cache.ParsedTemplate
  alias SferaDoc.Pdf.{HotCache, ObjectStore}

  @doc """
  Renders a template to a PDF binary.

  Options:
  - `:version` — render a specific version instead of the active one
  - `:chromic_pdf` — extra options passed to `ChromicPDF.print_to_pdf/2`

  Returns `{:ok, pdf_binary}` or `{:error, reason}`.
  """
  @spec render(String.t(), map(), keyword()) :: {:ok, binary()} | {:error, any()}
  def render(name, assigns, opts \\ []) do
    start = System.monotonic_time()
    meta = %{template_name: name}

    :telemetry.execute([:sfera_doc, :render, :start], %{system_time: System.system_time()}, meta)

    result = do_render(name, assigns, opts)

    case result do
      {:ok, _pdf} ->
        duration = System.monotonic_time() - start
        :telemetry.execute([:sfera_doc, :render, :stop], %{duration: duration}, meta)

      {:error, reason} ->
        duration = System.monotonic_time() - start

        :telemetry.execute(
          [:sfera_doc, :render, :exception],
          %{duration: duration},
          Map.put(meta, :error, reason)
        )
    end

    result
  end

  defp do_render(name, assigns, opts) do
    with {:ok, template} <- fetch_template(name, opts),
         :ok <- Template.validate_variables(template, assigns),
         {:ok, pdf} <- render_or_cached(template, assigns, opts) do
      {:ok, pdf}
    end
  end

  defp fetch_template(name, opts) do
    case Keyword.get(opts, :version) do
      nil -> Store.get(name)
      version -> Store.get_version(name, version)
    end
  end

  defp render_or_cached(template, assigns, opts) do
    hash = assigns_hash(assigns)

    with :miss <- HotCache.get(template.name, template.version, hash),
         :miss <- object_store_get(template.name, template.version, hash),
         {:ok, ast} <- get_or_parse(template),
         {:ok, html} <- render_html(ast, assigns),
         {:ok, pdf} <- render_pdf(html, opts) do
      ObjectStore.put(template.name, template.version, hash, pdf)
      HotCache.put(template.name, template.version, hash, pdf)
      {:ok, pdf}
    end
  end

  # Fetches from object store and populates the hot cache on hit.
  defp object_store_get(name, version, hash) do
    case ObjectStore.get(name, version, hash) do
      {:ok, pdf} ->
        HotCache.put(name, version, hash, pdf)
        {:ok, pdf}

      :miss ->
        :miss
    end
  end

  defp get_or_parse(template) do
    case ParsedTemplate.get(template.name, template.version) do
      {:ok, ast} ->
        {:ok, ast}

      :miss ->
        case Solid.parse(template.body) do
          {:ok, ast} ->
            ParsedTemplate.put(template.name, template.version, ast)
            {:ok, ast}

          {:error, %Solid.TemplateError{} = error} ->
            {:error, {:template_parse_error, error}}
        end
    end
  end

  defp render_html(ast, assigns) do
    case Solid.render(ast, assigns) do
      {:ok, iolist, []} ->
        {:ok, IO.iodata_to_binary(iolist)}

      {:ok, iolist, warnings} ->
        Logger.warning("SferaDoc: template rendering warnings: #{inspect(warnings)}")
        {:ok, IO.iodata_to_binary(iolist)}

      {:error, errors, partial_iolist} ->
        {:error, {:template_render_error, errors, IO.iodata_to_binary(partial_iolist)}}
    end
  end

  defp render_pdf(html, opts) do
    extra_opts = Keyword.get(opts, :chromic_pdf, [])
    pdf_opts = Keyword.merge([output: :binary], extra_opts)

    case ChromicPDF.print_to_pdf({:html, html}, pdf_opts) do
      {:ok, pdf} -> {:ok, pdf}
      other -> {:error, {:chromic_pdf_error, other}}
    end
  end

  defp assigns_hash(assigns) do
    assigns
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:md5, &1))
    |> Base.encode16(case: :lower)
  end
end
