defmodule SferaDoc.TemplateEngine do
  @moduledoc """
  Facade for the pluggable template engine.

  Delegates `parse/1` and `render/2` to the adapter module configured via:

      config :sfera_doc, :template_engine,
        adapter: MyApp.CustomTemplateEngine

  The default adapter is `SferaDoc.TemplateEngine.Solid` (Liquid syntax via the
  `Solid` library). Custom adapters must implement the
  `SferaDoc.TemplateEngine.Adapter` behaviour.
  """

  alias SferaDoc.Config

  @doc """
  Parses a template body string into an AST.

  Returns `{:ok, ast}` on success or `{:error, reason}` on parse failure.
  The AST is opaque and should only be passed to `render/2`.
  """
  @spec parse(String.t()) :: {:ok, term()} | {:error, any()}
  def parse(template_body), do: Config.template_engine_adapter().parse(template_body)

  @doc """
  Renders a previously parsed AST with the given assigns map.

  Returns `{:ok, html_binary}` on success or `{:error, reason}` on failure.
  """
  @spec render(term(), map()) :: {:ok, binary()} | {:error, any()}
  def render(ast, assigns), do: Config.template_engine_adapter().render(ast, assigns)
end
