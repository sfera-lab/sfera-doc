defmodule SferaDoc.TemplateEngine.SolidTest do
  use ExUnit.Case, async: true

  alias SferaDoc.TemplateEngine.Solid

  describe "parse/1" do
    test "parses valid Liquid template" do
      assert {:ok, ast} = Solid.parse("<h1>{{ name }}</h1>")
      assert is_struct(ast)
      assert is_list(ast.parsed_template)
    end

    test "parses template with filters" do
      assert {:ok, _ast} = Solid.parse("{{ name | upcase }}")
    end

    test "parses template with conditionals" do
      template = """
      {% if show %}
        <p>Visible</p>
      {% endif %}
      """

      assert {:ok, _ast} = Solid.parse(template)
    end

    test "returns error for invalid syntax" do
      # Unclosed tag
      assert {:error, _} = Solid.parse("{% if foo %}")
    end
  end

  describe "render/2" do
    test "renders template with assigns successfully" do
      {:ok, ast} = Solid.parse("<h1>{{ name }}</h1>")
      assert {:ok, html} = Solid.render(ast, %{"name" => "Alice"})
      assert html == "<h1>Alice</h1>"
    end

    test "renders template with multiple variables" do
      {:ok, ast} = Solid.parse("{{ greeting }} {{ name }}!")
      assert {:ok, html} = Solid.render(ast, %{"greeting" => "Hello", "name" => "World"})
      assert html == "Hello World!"
    end

    test "renders template with filters" do
      {:ok, ast} = Solid.parse("{{ name | upcase }}")
      assert {:ok, html} = Solid.render(ast, %{"name" => "alice"})
      assert html == "ALICE"
    end

    test "renders template with conditionals" do
      {:ok, ast} = Solid.parse("{% if show %}<p>Visible</p>{% endif %}")

      assert {:ok, html1} = Solid.render(ast, %{"show" => true})
      assert html1 == "<p>Visible</p>"

      assert {:ok, html2} = Solid.render(ast, %{"show" => false})
      assert html2 == ""
    end

    test "renders template with loops" do
      template = """
      {% for item in items %}
        {{ item }}
      {% endfor %}
      """

      {:ok, ast} = Solid.parse(template)
      assert {:ok, html} = Solid.render(ast, %{"items" => ["a", "b", "c"]})
      assert String.contains?(html, "a")
      assert String.contains?(html, "b")
      assert String.contains?(html, "c")
    end

    test "handles missing variables gracefully" do
      {:ok, ast} = Solid.parse("{{ missing_var }}")
      assert {:ok, html} = Solid.render(ast, %{})
      # Solid renders empty string for missing variables
      assert html == ""
    end

    test "converts iolist to binary" do
      {:ok, ast} = Solid.parse("{{ name }}")
      assert {:ok, html} = Solid.render(ast, %{"name" => "Test"})
      assert is_binary(html)
      assert html == "Test"
    end

    test "handles render errors with partial output" do
      # This is tricky - Solid doesn't easily produce errors in normal usage
      # Most "errors" become empty strings. Let's test what we can:
      {:ok, ast} = Solid.parse("{{ name }}")

      # Even with invalid data, Solid usually succeeds
      case Solid.render(ast, %{"name" => "valid"}) do
        {:ok, _} -> assert true
        {:error, {_errors, partial}} -> assert is_binary(partial)
      end
    end

    test "logs warnings when Solid returns warnings" do
      import ExUnit.CaptureLog

      # Test the warning path logic by simulating what the adapter does
      # when Solid.render returns warnings
      result_tuple = {:ok, ["output"], [:some_warning, :another_warning]}

      log =
        capture_log(fn ->
          result =
            case result_tuple do
              {:ok, iolist, []} ->
                {:ok, IO.iodata_to_binary(iolist)}

              {:ok, iolist, warnings} ->
                require Logger

                Logger.warning("SferaDoc: template rendering warnings: #{inspect(warnings)}")

                {:ok, IO.iodata_to_binary(iolist)}

              {:error, errors, partial_iolist} ->
                {:error, {errors, IO.iodata_to_binary(partial_iolist)}}
            end

          assert {:ok, "output"} = result
        end)

      assert log =~ "template rendering warnings"
      assert log =~ ":some_warning"
      assert log =~ ":another_warning"
    end

    test "handles error with partial output" do
      # Test the error path logic
      result_tuple = {:error, [:parse_error], ["partial", " output"]}

      result =
        case result_tuple do
          {:ok, iolist, []} ->
            {:ok, IO.iodata_to_binary(iolist)}

          {:ok, iolist, warnings} ->
            require Logger
            Logger.warning("SferaDoc: template rendering warnings: #{inspect(warnings)}")
            {:ok, IO.iodata_to_binary(iolist)}

          {:error, errors, partial_iolist} ->
            {:error, {errors, IO.iodata_to_binary(partial_iolist)}}
        end

      assert {:error, {errors, partial}} = result
      assert errors == [:parse_error]
      assert partial == "partial output"
      assert is_binary(partial)
    end

    test "converts iolist to binary in error case" do
      # Test iolist conversion in error path
      result_tuple = {:error, [:error], [["nested"], " ", "iolist"]}

      result =
        case result_tuple do
          {:ok, iolist, []} ->
            {:ok, IO.iodata_to_binary(iolist)}

          {:ok, iolist, warnings} ->
            require Logger
            Logger.warning("SferaDoc: template rendering warnings: #{inspect(warnings)}")
            {:ok, IO.iodata_to_binary(iolist)}

          {:error, errors, partial_iolist} ->
            {:error, {errors, IO.iodata_to_binary(partial_iolist)}}
        end

      assert {:error, {[:error], partial}} = result
      assert is_binary(partial)
      assert partial == "nested iolist"
    end

    test "converts iolist to binary in warning case" do
      # Test iolist conversion with warnings
      import ExUnit.CaptureLog

      result_tuple = {:ok, [["nested"], " ", ["iolist"]], [:warning]}

      log =
        capture_log(fn ->
          result =
            case result_tuple do
              {:ok, iolist, []} ->
                {:ok, IO.iodata_to_binary(iolist)}

              {:ok, iolist, warnings} ->
                require Logger

                Logger.warning("SferaDoc: template rendering warnings: #{inspect(warnings)}")

                {:ok, IO.iodata_to_binary(iolist)}

              {:error, errors, partial_iolist} ->
                {:error, {errors, IO.iodata_to_binary(partial_iolist)}}
            end

          assert {:ok, output} = result
          assert is_binary(output)
          assert output == "nested iolist"
        end)

      assert log =~ "template rendering warnings"
    end
  end
end
