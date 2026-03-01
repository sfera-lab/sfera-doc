# if Code.ensure_loaded?(Ecto.Adapters.SQLite3) do
#   defmodule SferaDoc.Store.EctoTest do
#     use SferaDoc.EctoCase, async: false

#     @moduletag :ecto

#     alias SferaDoc.{Store, Template}

#     test "create and retrieve a template" do
#       template = %Template{name: "hello", body: "Hello {{ name }}!"}
#       {:ok, saved} = Store.put(template)

#       assert saved.name == "hello"
#       assert saved.version == 1
#       assert saved.is_active == true

#       {:ok, fetched} = Store.get("hello")
#       assert fetched.body == "Hello {{ name }}!"
#     end

#     test "put creates a new version and deactivates the previous" do
#       {:ok, v1} = Store.put(%Template{name: "doc", body: "v1"})
#       {:ok, v2} = Store.put(%Template{name: "doc", body: "v2"})

#       assert v1.version == 1
#       assert v2.version == 2
#       assert v2.is_active == true

#       {:ok, active} = Store.get("doc")
#       assert active.body == "v2"
#     end

#     test "get_version returns a specific version" do
#       Store.put(%Template{name: "doc", body: "v1"})
#       Store.put(%Template{name: "doc", body: "v2"})

#       {:ok, v1} = Store.get_version("doc", 1)
#       assert v1.body == "v1"
#       assert v1.is_active == false
#     end

#     test "get returns :not_found for missing template" do
#       assert {:error, :not_found} = Store.get("missing")
#     end

#     test "get_version returns :not_found for missing version" do
#       Store.put(%Template{name: "doc", body: "v1"})
#       assert {:error, :not_found} = Store.get_version("doc", 99)
#     end

#     test "list returns active templates ordered by name" do
#       Store.put(%Template{name: "b", body: "b"})
#       Store.put(%Template{name: "a", body: "a"})
#       Store.put(%Template{name: "a", body: "a2"})

#       {:ok, templates} = Store.list()
#       assert length(templates) == 2
#       assert Enum.all?(templates, & &1.is_active)
#       assert [first, second] = templates
#       assert first.name == "a"
#       assert second.name == "b"
#     end

#     test "list_versions returns all versions descending" do
#       Store.put(%Template{name: "doc", body: "v1"})
#       Store.put(%Template{name: "doc", body: "v2"})
#       Store.put(%Template{name: "doc", body: "v3"})

#       {:ok, versions} = Store.list_versions("doc")
#       assert length(versions) == 3
#       assert [v3, v2, v1] = versions
#       assert v3.version == 3
#       assert v2.version == 2
#       assert v1.version == 1
#     end

#     test "activate_version switches the active version" do
#       Store.put(%Template{name: "doc", body: "v1"})
#       Store.put(%Template{name: "doc", body: "v2"})

#       {:ok, activated} = Store.activate_version("doc", 1)
#       assert activated.version == 1
#       assert activated.is_active == true

#       {:ok, active} = Store.get("doc")
#       assert active.version == 1
#     end

#     test "activate_version for non-existent version returns :not_found" do
#       Store.put(%Template{name: "doc", body: "v1"})
#       assert {:error, :not_found} = Store.activate_version("doc", 99)
#     end

#     test "activate_version is idempotent when version is already active" do
#       Store.put(%Template{name: "doc", body: "v1"})

#       {:ok, first} = Store.activate_version("doc", 1)
#       {:ok, second} = Store.activate_version("doc", 1)

#       assert first.version == 1
#       assert second.version == 1
#       assert second.is_active == true
#     end

#     test "delete removes all versions" do
#       Store.put(%Template{name: "doc", body: "v1"})
#       Store.put(%Template{name: "doc", body: "v2"})

#       :ok = Store.delete("doc")

#       assert {:error, :not_found} = Store.get("doc")
#       {:ok, []} = Store.list_versions("doc")
#     end

#     test "delete is idempotent for non-existent template" do
#       assert :ok = Store.delete("never_existed")
#     end

#     test "put returns validation error for blank name" do
#       assert {:error, {:validation, changeset}} =
#                SferaDoc.Store.Ecto.put(%Template{name: "", body: "body"})

#       assert changeset.errors[:name]
#     end

#     test "put stores variables_schema" do
#       schema = %{"type" => "object", "properties" => %{"name" => %{"type" => "string"}}}
#       {:ok, saved} = Store.put(%Template{name: "schema_test", body: "Hello", variables_schema: schema})

#       {:ok, fetched} = Store.get("schema_test")
#       assert fetched.variables_schema == schema
#     end
#   end
# end
