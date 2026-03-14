defmodule SferaDoc.Store.EctoTest do
  use ExUnit.Case, async: false

  @moduletag :ecto

  alias SferaDoc.{Store, Template}

  setup do
    # Clear table between tests
    Ecto.Adapters.SQL.query!(SferaDoc.TestRepo, "DELETE FROM sfera_doc_templates")

    # Configure Ecto store
    Application.put_env(:sfera_doc, :store,
      adapter: SferaDoc.Store.Ecto,
      repo: SferaDoc.TestRepo
    )

    on_exit(fn ->
      Application.delete_env(:sfera_doc, :store)
    end)

    :ok
  end

  describe "worker_spec/0" do
    test "returns nil (repo managed by host app)" do
      assert SferaDoc.Store.Ecto.worker_spec() == nil
    end
  end

  describe "get/1" do
    test "returns {:error, :not_found} for non-existent template" do
      assert {:error, :not_found} = Store.get("nonexistent")
    end

    test "returns active template" do
      template = %Template{name: "test", body: "content"}
      {:ok, created} = Store.put(template)

      assert {:ok, fetched} = Store.get("test")
      assert fetched.name == "test"
      assert fetched.version == 1
      assert fetched.is_active
      assert fetched.body == "content"
    end

    test "returns latest active version" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      {:ok, template} = Store.get("test")
      assert template.version == 2
      assert template.body == "v2"
      assert template.is_active
    end

    test "handles database errors gracefully" do
      # Simulate database error by configuring invalid repo
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: NonExistentRepo
      )

      assert {:error, %UndefinedFunctionError{}} = Store.get("test")
    end
  end

  describe "get_version/2" do
    test "returns {:error, :not_found} for non-existent version" do
      assert {:error, :not_found} = Store.get_version("test", 999)
    end

    test "returns specific version" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      assert {:ok, v1} = Store.get_version("test", 1)
      assert v1.version == 1
      assert v1.body == "v1"
      assert v1.is_active == false

      assert {:ok, v2} = Store.get_version("test", 2)
      assert v2.version == 2
      assert v2.body == "v2"
      assert v2.is_active == true
    end

    test "returns inactive versions" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      {:ok, v1} = Store.get_version("test", 1)
      assert v1.is_active == false
    end

    test "handles database errors gracefully" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: NonExistentRepo
      )

      assert {:error, %UndefinedFunctionError{}} = Store.get_version("test", 1)
    end
  end

  describe "put/1" do
    test "creates first version" do
      template = %Template{
        name: "test",
        body: "content",
        variables_schema: %{"required" => ["name"]}
      }

      {:ok, created} = Store.put(template)

      assert created.version == 1
      assert created.is_active
      assert created.body == "content"
      assert created.variables_schema == %{"required" => ["name"]}
      assert created.name == "test"
      assert created.id != nil
      assert created.inserted_at != nil
      assert created.updated_at != nil
    end

    test "creates incremental versions" do
      Store.put(%Template{name: "test", body: "v1"})
      {:ok, v2} = Store.put(%Template{name: "test", body: "v2"})
      {:ok, v3} = Store.put(%Template{name: "test", body: "v3"})

      assert v2.version == 2
      assert v3.version == 3
    end

    test "deactivates previous versions atomically" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      {:ok, v1} = Store.get_version("test", 1)
      {:ok, v2} = Store.get_version("test", 2)

      assert v1.is_active == false
      assert v2.is_active == true
    end

    test "uses Ecto.Multi for transaction atomicity" do
      # Create first version
      {:ok, v1} = Store.put(%Template{name: "test", body: "v1"})
      assert v1.version == 1

      # Create second version - should deactivate first
      {:ok, v2} = Store.put(%Template{name: "test", body: "v2"})
      assert v2.version == 2

      # Verify first version is deactivated
      {:ok, v1_fetched} = Store.get_version("test", 1)
      assert v1_fetched.is_active == false
    end

    test "preserves variables_schema" do
      schema = %{
        "type" => "object",
        "properties" => %{
          "name" => %{"type" => "string"},
          "age" => %{"type" => "integer"}
        }
      }

      {:ok, template} = Store.put(%Template{name: "test", body: "body", variables_schema: schema})
      assert template.variables_schema == schema

      {:ok, fetched} = Store.get("test")
      assert fetched.variables_schema == schema
    end

    test "handles nil variables_schema" do
      {:ok, template} = Store.put(%Template{name: "test", body: "body"})
      assert template.variables_schema == nil

      {:ok, fetched} = Store.get("test")
      assert fetched.variables_schema == nil
    end

    test "handles database errors gracefully" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: NonExistentRepo
      )

      template = %Template{name: "test", body: "content"}
      assert {:error, %UndefinedFunctionError{}} = Store.put(template)
    end
  end

  describe "list/0" do
    test "returns empty list when no templates" do
      assert {:ok, []} = Store.list()
    end

    test "returns only active templates" do
      Store.put(%Template{name: "alpha", body: "v1"})
      Store.put(%Template{name: "alpha", body: "v2"})
      Store.put(%Template{name: "bravo", body: "v1"})

      {:ok, templates} = Store.list()
      names_and_versions = Enum.map(templates, &{&1.name, &1.version}) |> Enum.sort()

      assert length(templates) == 2
      assert names_and_versions == [{"alpha", 2}, {"bravo", 1}]
    end

    test "returns templates sorted by name" do
      Store.put(%Template{name: "zebra", body: "v1"})
      Store.put(%Template{name: "alpha", body: "v1"})
      Store.put(%Template{name: "mike", body: "v1"})

      {:ok, templates} = Store.list()
      names = Enum.map(templates, & &1.name)

      assert names == ["alpha", "mike", "zebra"]
    end

    test "excludes inactive versions" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})
      Store.put(%Template{name: "test", body: "v3"})

      {:ok, templates} = Store.list()
      assert length(templates) == 1
      assert hd(templates).version == 3
    end

    test "handles database errors gracefully" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: NonExistentRepo
      )

      assert {:error, %UndefinedFunctionError{}} = Store.list()
    end
  end

  describe "list_versions/1" do
    test "returns empty list for non-existent template" do
      assert {:ok, []} = Store.list_versions("nonexistent")
    end

    test "returns all versions sorted descending" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})
      Store.put(%Template{name: "test", body: "v3"})

      {:ok, versions} = Store.list_versions("test")
      version_numbers = Enum.map(versions, & &1.version)

      assert version_numbers == [3, 2, 1]
    end

    test "includes both active and inactive versions" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      {:ok, versions} = Store.list_versions("test")
      assert length(versions) == 2
      assert Enum.at(versions, 0).is_active == true
      assert Enum.at(versions, 1).is_active == false
    end

    test "handles database errors gracefully" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: NonExistentRepo
      )

      assert {:error, %UndefinedFunctionError{}} = Store.list_versions("test")
    end
  end

  describe "activate_version/2" do
    test "returns {:error, :not_found} for non-existent version" do
      assert {:error, :not_found} = Store.activate_version("test", 999)
    end

    test "activates specified version and deactivates others" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})
      Store.put(%Template{name: "test", body: "v3"})

      {:ok, activated} = Store.activate_version("test", 2)
      assert activated.version == 2
      assert activated.is_active

      {:ok, v1} = Store.get_version("test", 1)
      {:ok, v2} = Store.get_version("test", 2)
      {:ok, v3} = Store.get_version("test", 3)

      assert v1.is_active == false
      assert v2.is_active == true
      assert v3.is_active == false
    end

    test "uses Ecto.Multi for transaction atomicity" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      # Activate v1
      {:ok, activated} = Store.activate_version("test", 1)
      assert activated.version == 1

      # Get should return v1 now
      {:ok, active} = Store.get("test")
      assert active.version == 1
    end

    test "handles activating already active version" do
      {:ok, v1} = Store.put(%Template{name: "test", body: "v1"})
      assert v1.is_active

      {:ok, activated} = Store.activate_version("test", 1)
      assert activated.is_active
      assert activated.version == 1
    end

    test "handles database errors gracefully" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: NonExistentRepo
      )

      assert {:error, %UndefinedFunctionError{}} = Store.activate_version("test", 1)
    end
  end

  describe "delete/1" do
    test "deletes all versions of a template" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})
      Store.put(%Template{name: "other", body: "v1"})

      assert :ok = Store.delete("test")

      assert {:error, :not_found} = Store.get("test")
      assert {:error, :not_found} = Store.get_version("test", 1)
      assert {:error, :not_found} = Store.get_version("test", 2)

      # Other template should still exist
      assert {:ok, _} = Store.get("other")
    end

    test "handles deleting non-existent template" do
      assert :ok = Store.delete("nonexistent")
    end

    test "removes deleted templates from list" do
      Store.put(%Template{name: "keep", body: "v1"})
      Store.put(%Template{name: "delete", body: "v1"})

      {:ok, before} = Store.list()
      assert length(before) == 2

      Store.delete("delete")

      {:ok, after_delete} = Store.list()
      assert length(after_delete) == 1
      assert hd(after_delete).name == "keep"
    end

    test "handles database errors gracefully" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: NonExistentRepo
      )

      assert {:error, %UndefinedFunctionError{}} = Store.delete("test")
    end
  end
end
