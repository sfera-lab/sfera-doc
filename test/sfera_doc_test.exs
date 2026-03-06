# defmodule SferaDocTest do
#   use ExUnit.Case, async: false

#   @moduletag :ets

#   setup do
#     Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
#     Application.put_env(:sfera_doc, :cache, enabled: false)

#     case Process.whereis(SferaDoc.Store.ETS) do
#       nil -> start_supervised!(SferaDoc.Store.ETS)
#       _pid -> SferaDoc.Store.ETS.reset()
#     end

#     :ok
#   end

#   test "create_template and get_template" do
#     {:ok, t} = SferaDoc.create_template("welcome", "Hello {{ name }}!")
#     assert t.version == 1
#     assert t.is_active == true

#     {:ok, fetched} = SferaDoc.get_template("welcome")
#     assert fetched.body == "Hello {{ name }}!"
#   end

#   test "create_template creates a new version" do
#     {:ok, _v1} = SferaDoc.create_template("doc", "v1")
#     {:ok, v2} = SferaDoc.create_template("doc", "v2")
#     assert v2.version == 2

#     {:ok, active} = SferaDoc.get_template("doc")
#     assert active.body == "v2"
#   end

#   test "create_template deactivates previous version" do
#     {:ok, _v1} = SferaDoc.create_template("doc", "v1")
#     {:ok, _v2} = SferaDoc.create_template("doc", "v2")

#     {:ok, v1} = SferaDoc.get_template("doc", version: 1)
#     assert v1.is_active == false
#   end

#   test "get_template with version option" do
#     SferaDoc.create_template("doc", "v1")
#     SferaDoc.create_template("doc", "v2")

#     {:ok, v1} = SferaDoc.get_template("doc", version: 1)
#     assert v1.body == "v1"
#   end

#   test "get_template returns :not_found for missing template" do
#     assert {:error, :not_found} = SferaDoc.get_template("nonexistent")
#   end

#   test "list_templates returns active versions" do
#     SferaDoc.create_template("a", "a")
#     SferaDoc.create_template("b", "b")

#     {:ok, templates} = SferaDoc.list_templates()
#     names = Enum.map(templates, & &1.name)
#     assert length(templates) == 2
#     assert "a" in names
#     assert "b" in names
#   end

#   test "list_templates returns one entry per name after updates" do
#     SferaDoc.create_template("doc", "v1")
#     SferaDoc.create_template("doc", "v2")

#     {:ok, templates} = SferaDoc.list_templates()
#     assert length(templates) == 1
#     assert hd(templates).body == "v2"
#   end

#   test "list_versions returns all versions" do
#     SferaDoc.create_template("doc", "v1")
#     SferaDoc.create_template("doc", "v2")

#     {:ok, versions} = SferaDoc.list_versions("doc")
#     assert length(versions) == 2
#   end

#   test "list_versions returns empty list for unknown template" do
#     {:ok, versions} = SferaDoc.list_versions("nonexistent")
#     assert versions == []
#   end

#   test "activate_version rolls back to previous version" do
#     SferaDoc.create_template("doc", "v1")
#     SferaDoc.create_template("doc", "v2")

#     {:ok, _} = SferaDoc.activate_version("doc", 1)
#     {:ok, active} = SferaDoc.get_template("doc")
#     assert active.version == 1
#     assert active.body == "v1"
#   end

#   test "activate_version deactivates previously active version" do
#     SferaDoc.create_template("doc", "v1")
#     SferaDoc.create_template("doc", "v2")

#     SferaDoc.activate_version("doc", 1)

#     {:ok, v2} = SferaDoc.get_template("doc", version: 2)
#     assert v2.is_active == false
#   end

#   test "activate_version returns :not_found for unknown version" do
#     SferaDoc.create_template("doc", "v1")
#     assert {:error, :not_found} = SferaDoc.activate_version("doc", 99)
#   end

#   test "delete_template removes template" do
#     SferaDoc.create_template("temp", "body")
#     :ok = SferaDoc.delete_template("temp")

#     assert {:error, :not_found} = SferaDoc.get_template("temp")
#   end

#   test "delete_template removes all versions" do
#     SferaDoc.create_template("doc", "v1")
#     SferaDoc.create_template("doc", "v2")
#     :ok = SferaDoc.delete_template("doc")

#     {:ok, versions} = SferaDoc.list_versions("doc")
#     assert versions == []
#   end

#   test "create_template with variables_schema" do
#     {:ok, t} =
#       SferaDoc.create_template(
#         "invoice",
#         "Invoice for {{ customer }}",
#         variables_schema: %{"required" => ["customer"]}
#       )

#     assert t.variables_schema == %{"required" => ["customer"]}
#   end

#   test "create_template accepts variables_schema" do
#     SferaDoc.create_template("doc", "v1", variables_schema: %{"required" => ["name"]})

#     {:ok, v2} =
#       SferaDoc.create_template("doc", "v2", variables_schema: %{"required" => ["name", "date"]})

#     assert v2.variables_schema == %{"required" => ["name", "date"]}
#   end
# end
