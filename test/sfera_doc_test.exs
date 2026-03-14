defmodule SferaDocTest do
  use ExUnit.Case, async: false

  alias SferaDoc.{Template, TestObjectStore, TestStore, TestSupport}

  setup do
    Application.put_env(:sfera_doc, :store, adapter: TestStore)
    Application.put_env(:sfera_doc, :template_engine, adapter: SferaDoc.TestTemplateEngine)
    Application.put_env(:sfera_doc, :pdf_engine, adapter: SferaDoc.TestPdfEngine)
    Application.put_env(:sfera_doc, :pdf_object_store, adapter: TestObjectStore)
    Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: nil)
    Application.put_env(:sfera_doc, :cache, enabled: false)

    TestStore.reset()
    TestObjectStore.reset()
    TestSupport.reset_counters()

    :ok
  end

  defp assigns_hash(assigns) do
    assigns
    |> :erlang.term_to_binary()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  describe "create_template/3" do
    test "versions templates and keeps latest active" do
      assert {:ok, v1} =
               SferaDoc.create_template(
                 "invoice",
                 "<h1>v1</h1>",
                 variables_schema: %{"required" => ["name"]}
               )

      assert v1.version == 1
      assert v1.is_active
      assert v1.variables_schema == %{"required" => ["name"]}

      assert {:ok, v2} = SferaDoc.create_template("invoice", "<h1>v2</h1>")
      assert v2.version == 2
      assert v2.is_active

      assert {:ok, versions} = SferaDoc.list_versions("invoice")

      assert Enum.map(versions, &{&1.version, &1.is_active}) ==
               [{2, true}, {1, false}]
    end
  end

  describe "get_template/2" do
    test "returns active or specific version" do
      {:ok, _} = SferaDoc.create_template("invoice", "<h1>v1</h1>")
      {:ok, _} = SferaDoc.create_template("invoice", "<h1>v2</h1>")

      assert {:ok, %Template{version: 2, is_active: true}} = SferaDoc.get_template("invoice")
      assert {:ok, %Template{version: 1}} = SferaDoc.get_template("invoice", version: 1)
    end
  end

  describe "list_templates/0" do
    test "returns active templates only" do
      {:ok, _} = SferaDoc.create_template("alpha", "v1")
      {:ok, _} = SferaDoc.create_template("alpha", "v2")
      {:ok, _} = SferaDoc.create_template("bravo", "v1")

      {:ok, templates} = SferaDoc.list_templates()

      names = templates |> Enum.map(&{&1.name, &1.version}) |> Enum.sort()
      assert names == [{"alpha", 2}, {"bravo", 1}]
    end
  end

  describe "list_versions/1" do
    test "returns versions in descending order" do
      {:ok, _} = SferaDoc.create_template("invoice", "v1")
      {:ok, _} = SferaDoc.create_template("invoice", "v2")

      {:ok, versions} = SferaDoc.list_versions("invoice")
      assert Enum.map(versions, & &1.version) == [2, 1]
    end
  end

  describe "activate_version/2" do
    test "switches active version" do
      {:ok, _} = SferaDoc.create_template("invoice", "v1")
      {:ok, _} = SferaDoc.create_template("invoice", "v2")

      assert {:ok, %Template{version: 1, is_active: true}} =
               SferaDoc.activate_version("invoice", 1)

      {:ok, versions} = SferaDoc.list_versions("invoice")
      assert Enum.map(versions, &{&1.version, &1.is_active}) == [{2, false}, {1, true}]
    end
  end

  describe "delete_template/1" do
    test "removes all versions" do
      {:ok, _} = SferaDoc.create_template("invoice", "v1")
      assert :ok = SferaDoc.delete_template("invoice")
      assert {:error, :not_found} = SferaDoc.get_template("invoice")
      assert {:ok, []} = SferaDoc.list_versions("invoice")
    end
  end

  describe "render/3" do
    test "renders and stores PDF in object store" do
      {:ok, template} =
        SferaDoc.create_template(
          "welcome",
          "<h1>Hello {{ name }}</h1>",
          variables_schema: %{"required" => ["name"]}
        )

      assigns = %{"name" => "Alice"}
      assert {:ok, pdf} = SferaDoc.render("welcome", assigns)
      assert String.starts_with?(pdf, "PDF_BINARY:")

      hash = assigns_hash(assigns)
      assert {:ok, ^pdf} = TestObjectStore.get("welcome", template.version, hash)
      assert TestSupport.get_counter(:object_store_put) == 1
    end

    test "returns cached PDF from object store without rendering" do
      {:ok, template} = SferaDoc.create_template("cached", "v1")
      assigns = %{"name" => "Bob"}
      hash = assigns_hash(assigns)
      pdf = "PDF_BINARY:cached"

      assert :ok = TestObjectStore.put("cached", template.version, hash, pdf)

      assert {:ok, ^pdf} = SferaDoc.render("cached", assigns)
      assert TestSupport.get_counter(:pdf_render) == 0
      assert TestSupport.get_counter(:template_parse) == 0
      assert TestSupport.get_counter(:template_render) == 0
    end

    test "returns :not_found when template is missing" do
      assert {:error, :not_found} = SferaDoc.render("missing", %{})
    end

    test "validates required variables" do
      {:ok, _} =
        SferaDoc.create_template(
          "needs_name",
          "Hi {{ name }}",
          variables_schema: %{"required" => ["name"]}
        )

      assert {:error, {:missing_variables, ["name"]}} = SferaDoc.render("needs_name", %{})
    end

    test "surfaces template parse errors" do
      {:ok, _} = SferaDoc.create_template("bad", "PARSE_ERROR")

      assert {:error, {:template_parse_error, :bad_parse}} = SferaDoc.render("bad", %{})
    end

    test "surfaces template render errors (tuple form)" do
      {:ok, _} = SferaDoc.create_template("render_error", "body")

      assert {:error, {:template_render_error, ["bad"], "<p>partial</p>"}} =
               SferaDoc.render("render_error", %{"render_error" => "tuple"})
    end

    test "surfaces template render errors (other form)" do
      {:ok, _} = SferaDoc.create_template("render_error_other", "body")

      assert {:error, {:template_render_error, :render_boom}} =
               SferaDoc.render("render_error_other", %{"render_error" => "other"})
    end

    test "surfaces PDF engine errors" do
      {:ok, _} = SferaDoc.create_template("pdf_error", "PDF_ERROR")

      assert {:error, :pdf_failed} = SferaDoc.render("pdf_error", %{})
    end

    test "supports version option" do
      {:ok, _} = SferaDoc.create_template("versioned", "v1")
      {:ok, v2} = SferaDoc.create_template("versioned", "v2")

      assert {:ok, pdf} = SferaDoc.render("versioned", %{}, version: 1)
      assert String.contains?(pdf, "v1")
      assert v2.version == 2
    end
  end
end
