defmodule SferaDoc.TemplateEngine do
  @moduledoc false

  alias SferaDoc.Config

  @spec parse(String.t()) :: {:ok, term()} | {:error, any()}
  def parse(template_body), do: Config.template_engine_adapter().parse(template_body)

  @spec render(term(), map()) :: {:ok, binary()} | {:error, any()}
  def render(ast, assigns), do: Config.template_engine_adapter().render(ast, assigns)
end
