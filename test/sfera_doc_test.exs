defmodule SferaDocTest do
  use ExUnit.Case, async: false

  @moduletag :ets

  setup do
    Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
    Application.put_env(:sfera_doc, :cache, enabled: false)

    case Process.whereis(SferaDoc.Store.ETS) do
      nil -> start_supervised!(SferaDoc.Store.ETS)
      _pid -> SferaDoc.Store.ETS.reset()
    end

    :ok
  end

  test "create_template and get_template" do
    {:ok, t} = SferaDoc.create_template("welcome", "Hello {{ name }}!")
    assert t.version == 1
    assert t.is_active == true

    {:ok, fetched} = SferaDoc.get_template("welcome")
    assert fetched.body == "Hello {{ name }}!"
  end

  test "update_template creates a new version" do
    SferaDoc.create_template("doc", "v1")
    {:ok, v2} = SferaDoc.update_template("doc", "v2")
    assert v2.version == 2

    {:ok, active} = SferaDoc.get_template("doc")
    assert active.body == "v2"
  end

  test "get_template with version option" do
    SferaDoc.create_template("doc", "v1")
    SferaDoc.update_template("doc", "v2")

    {:ok, v1} = SferaDoc.get_template("doc", version: 1)
    assert v1.body == "v1"
  end

  test "list_templates returns active versions" do
    SferaDoc.create_template("a", "a")
    SferaDoc.create_template("b", "b")

    {:ok, templates} = SferaDoc.list_templates()
    names = Enum.map(templates, & &1.name)
    assert "a" in names
    assert "b" in names
  end

  test "list_versions returns all versions" do
    SferaDoc.create_template("doc", "v1")
    SferaDoc.update_template("doc", "v2")

    {:ok, versions} = SferaDoc.list_versions("doc")
    assert length(versions) == 2
  end

  test "activate_version rolls back to previous version" do
    SferaDoc.create_template("doc", "v1")
    SferaDoc.update_template("doc", "v2")

    {:ok, _} = SferaDoc.activate_version("doc", 1)
    {:ok, active} = SferaDoc.get_template("doc")
    assert active.version == 1
    assert active.body == "v1"
  end

  test "delete_template removes template" do
    SferaDoc.create_template("temp", "body")
    :ok = SferaDoc.delete_template("temp")

    assert {:error, :not_found} = SferaDoc.get_template("temp")
  end

  test "create_template with variables_schema" do
    {:ok, t} =
      SferaDoc.create_template(
        "invoice",
        "Invoice for {{ customer }}",
        variables_schema: %{"required" => ["customer"]}
      )

    assert t.variables_schema == %{"required" => ["customer"]}
  end
end
