defmodule SferaDoc.TestTemplateEngine do
  @moduledoc false
  @behaviour SferaDoc.TemplateEngine.Adapter

  alias SferaDoc.TestSupport

  @impl true
  def parse("PARSE_ERROR"), do: {:error, :bad_parse}

  def parse(body) do
    TestSupport.increment(:template_parse)
    {:ok, {:ast, body}}
  end

  @impl true
  def render(_ast, %{"render_error" => "tuple"}) do
    TestSupport.increment(:template_render)
    {:error, {["bad"], "<p>partial</p>"}}
  end

  def render(_ast, %{"render_error" => "other"}) do
    TestSupport.increment(:template_render)
    {:error, :render_boom}
  end

  def render({:ast, body}, assigns) do
    TestSupport.increment(:template_render)
    {:ok, "<html>#{body}::#{inspect(assigns)}</html>"}
  end
end
