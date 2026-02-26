defmodule SferaDoc.TemplateEngine.Solid do
  @moduledoc """
  Default template engine adapter backed by `Solid`.
  """

  require Logger

  @behaviour SferaDoc.TemplateEngine.Adapter

  @impl true
  def parse(template_body), do: Solid.parse(template_body)

  @impl true
  def render(ast, assigns) do
    case Solid.render(ast, assigns) do
      {:ok, iolist, []} ->
        {:ok, IO.iodata_to_binary(iolist)}

      {:ok, iolist, warnings} ->
        Logger.warning("SferaDoc: template rendering warnings: #{inspect(warnings)}")
        {:ok, IO.iodata_to_binary(iolist)}

      {:error, errors, partial_iolist} ->
        {:error, {errors, IO.iodata_to_binary(partial_iolist)}}
    end
  end
end
