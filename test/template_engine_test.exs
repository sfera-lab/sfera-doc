# defmodule SferaDoc.TemplateEngineTest do
#   use ExUnit.Case, async: true

#   alias SferaDoc.TemplateEngine

#   # ---------------------------------------------------------------------------
#   # Stub adapter for testing delegation
#   # ---------------------------------------------------------------------------

#   defmodule StubAdapter do
#     @behaviour SferaDoc.TemplateEngine.Adapter

#     @impl true
#     def parse("bad template"), do: {:error, :parse_error}
#     def parse(body), do: {:ok, {:stub_ast, body}}

#     @impl true
#     def render({:stub_ast, body}, assigns) do
#       case Map.get(assigns, "fail") do
#         true -> {:error, :render_error}
#         _ -> {:ok, "rendered:#{body}"}
#       end
#     end
#   end

#   setup do
#     original = Application.get_env(:sfera_doc, :template_engine, [])

#     Application.put_env(:sfera_doc, :template_engine, adapter: StubAdapter)

#     on_exit(fn ->
#       Application.put_env(:sfera_doc, :template_engine, original)
#     end)

#     :ok
#   end

#   # ---------------------------------------------------------------------------
#   # parse/1
#   # ---------------------------------------------------------------------------

#   describe "parse/1" do
#     test "returns {:ok, ast} on success" do
#       assert {:ok, {:stub_ast, "hello {{ name }}"}} =
#                TemplateEngine.parse("hello {{ name }}")
#     end

#     test "returns {:error, reason} on parse failure" do
#       assert {:error, :parse_error} = TemplateEngine.parse("bad template")
#     end
#   end

#   # ---------------------------------------------------------------------------
#   # render/2
#   # ---------------------------------------------------------------------------

#   describe "render/2" do
#     test "returns {:ok, html} on success" do
#       {:ok, ast} = TemplateEngine.parse("my body")
#       assert {:ok, "rendered:my body"} = TemplateEngine.render(ast, %{})
#     end

#     test "returns {:error, reason} on render failure" do
#       {:ok, ast} = TemplateEngine.parse("my body")
#       assert {:error, :render_error} = TemplateEngine.render(ast, %{"fail" => true})
#     end
#   end

#   # ---------------------------------------------------------------------------
#   # Default adapter integration (uses real Solid)
#   # ---------------------------------------------------------------------------

#   describe "default Solid adapter integration" do
#     setup do
#       Application.put_env(:sfera_doc, :template_engine, [])
#       :ok
#     end

#     test "parse/1 returns {:ok, ast} for valid Liquid template" do
#       assert {:ok, _ast} = TemplateEngine.parse("Hello {{ name }}!")
#     end

#     test "round-trip parse and render" do
#       {:ok, ast} = TemplateEngine.parse("Hello {{ name }}!")
#       assert {:ok, html} = TemplateEngine.render(ast, %{"name" => "World"})
#       assert html == "Hello World!"
#     end

#     test "render with no assigns returns template with blanks for missing vars" do
#       {:ok, ast} = TemplateEngine.parse("Hello {{ name }}!")
#       assert {:ok, html} = TemplateEngine.render(ast, %{})
#       assert html == "Hello !"
#     end

#     test "parse/1 returns {:error, reason} for invalid Liquid syntax" do
#       assert {:error, _reason} = TemplateEngine.parse("{% if %}")
#     end
#   end
# end
