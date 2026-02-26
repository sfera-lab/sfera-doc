defmodule SferaDoc.TemplateEngine.Solid do
  @moduledoc """
  Wraps the `Solid` Liquid template engine for use within SferaDoc.

  Provides two operations:

  - `parse/1` — compiles a Liquid template string into a parsed AST
  - `render/2` — renders an AST with a map of assigns into an HTML binary

  Both functions return tagged tuples compatible with `with` chains so that
  callers do not need to know about `Solid`-specific error types.

  ## Examples

      iex> {:ok, ast} = SferaDoc.TemplateEngine.Solid.parse("Hello {{ name }}!")
      iex> SferaDoc.TemplateEngine.Solid.render(ast, %{"name" => "Alice"})
      {:ok, "Hello Alice!"}

      iex> SferaDoc.TemplateEngine.Solid.parse("Hello {{ name }")
      {:error, {:template_parse_error, _}}
  """

  require Logger

  @doc """
  Parses a Liquid template string into a `Solid` AST.

  Returns `{:ok, ast}` on success, or
  `{:error, {:template_parse_error, reason}}` if the template contains
  syntax errors.
  """
  @spec parse(String.t()) ::
          {:ok, term()} | {:error, {:template_parse_error, Solid.TemplateError.t()}}
  def parse(body) when is_binary(body) do
    case Solid.parse(body) do
      {:ok, ast} -> {:ok, ast}
      {:error, %Solid.TemplateError{} = error} -> {:error, {:template_parse_error, error}}
    end
  end

  @doc """
  Renders a parsed Solid AST with the given `assigns` map into an HTML binary.

  Returns `{:ok, html}` on success. Any warnings emitted by Solid are logged
  at the `:warning` level but do not prevent a successful return.

  Returns `{:error, {:template_render_error, errors, partial_html}}` if Solid
  encounters errors during rendering. `partial_html` contains whatever output
  Solid produced before failing and can be used for debugging.
  """
  @spec render(term(), map()) ::
          {:ok, String.t()} | {:error, {:template_render_error, list(), String.t()}}
  def render(ast, assigns) when is_map(assigns) do
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
end
