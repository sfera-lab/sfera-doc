defmodule SferaDoc.TemplateEngine.Adapter do
  @moduledoc """
  Behaviour for template engines used by SferaDoc.

  Implementations are responsible for parsing template source and rendering it
  into a binary output (typically HTML).

  ## Implementing a Custom Adapter

  1. `@behaviour SferaDoc.TemplateEngine.Adapter`
  2. Implement all callbacks: `parse/1` and `render/2`
  3. Configure the library to use your adapter:

         config :sfera_doc, :template_engine, adapter: MyApp.CustomTemplateEngine
  """

  @type ast :: term()
  @type reason :: any()

  @doc """
  Parses the given template source string into an intermediate AST.

  Returns `{:ok, ast}` on success, or `{:error, reason}` if the template is
  syntactically invalid.
  """
  @callback parse(String.t()) :: {:ok, ast()} | {:error, reason()}

  @doc """
  Renders the given AST with the provided assigns map into a binary.

  `assigns` is a map of variable bindings available within the template.

  Returns `{:ok, binary}` on success, or `{:error, reason}` on failure.
  """
  @callback render(ast(), map()) :: {:ok, binary()} | {:error, reason()}
end
