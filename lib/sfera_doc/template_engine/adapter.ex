defmodule SferaDoc.TemplateEngine.Adapter do
  @moduledoc """
  Behaviour for template engines used by SferaDoc.

  Implementations are responsible for parsing template source and rendering it
  into HTML.
  """

  @type ast :: term()
  @type reason :: any()

  @callback parse(String.t()) :: {:ok, ast()} | {:error, reason()}
  @callback render(ast(), map()) :: {:ok, binary()} | {:error, reason()}
end
