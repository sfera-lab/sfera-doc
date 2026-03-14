defmodule SferaDoc.TestStoreTest do
  use ExUnit.Case, async: false

  alias SferaDoc.{Template, TestStore}

  describe "reset/0" do
    test "handles non-existent table" do
      # Ensure table doesn't exist
      table = :sfera_doc_test_store

      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end

      # Reset should not crash even if table doesn't exist
      assert :ok = TestStore.reset()
    end

    test "deletes existing table and data" do
      # Create some data
      template = %Template{name: "test", body: "body"}
      TestStore.put(template)

      # Reset should delete everything
      assert :ok = TestStore.reset()
      table = :sfera_doc_test_store
      assert :ets.whereis(table) == :undefined
    end
  end

  describe "worker_spec/0" do
    test "returns nil" do
      assert TestStore.worker_spec() == nil
    end
  end

  describe "get/1" do
    setup do
      TestStore.reset()
      :ok
    end

    test "returns {:error, :not_found} for non-existent template" do
      assert {:error, :not_found} = TestStore.get("nonexistent")
    end

    test "returns active template" do
      template = %Template{name: "test", body: "body"}
      {:ok, created} = TestStore.put(template)

      assert {:ok, fetched} = TestStore.get("test")
      assert fetched.name == "test"
      assert fetched.version == 1
      assert fetched.is_active
    end

    test "returns latest active template after multiple versions" do
      TestStore.put(%Template{name: "test", body: "v1"})
      TestStore.put(%Template{name: "test", body: "v2"})

      {:ok, template} = TestStore.get("test")
      assert template.version == 2
      assert template.body == "v2"
      assert template.is_active
    end
  end

  describe "get_version/2" do
    setup do
      TestStore.reset()
      :ok
    end

    test "returns {:error, :not_found} for non-existent version" do
      assert {:error, :not_found} = TestStore.get_version("test", 999)
    end

    test "returns specific version" do
      TestStore.put(%Template{name: "test", body: "v1"})
      TestStore.put(%Template{name: "test", body: "v2"})

      assert {:ok, v1} = TestStore.get_version("test", 1)
      assert v1.version == 1
      assert v1.body == "v1"
      assert v1.is_active == false

      assert {:ok, v2} = TestStore.get_version("test", 2)
      assert v2.version == 2
      assert v2.body == "v2"
      assert v2.is_active == true
    end
  end

  describe "put/1" do
    setup do
      TestStore.reset()
      :ok
    end

    test "creates first version" do
      template = %Template{
        name: "test",
        body: "body",
        variables_schema: %{"required" => ["name"]}
      }

      {:ok, created} = TestStore.put(template)

      assert created.version == 1
      assert created.is_active
      assert created.body == "body"
      assert created.variables_schema == %{"required" => ["name"]}
      assert %DateTime{} = created.inserted_at
      assert %DateTime{} = created.updated_at
    end

    test "creates incremental versions" do
      TestStore.put(%Template{name: "test", body: "v1"})
      {:ok, v2} = TestStore.put(%Template{name: "test", body: "v2"})
      {:ok, v3} = TestStore.put(%Template{name: "test", body: "v3"})

      assert v2.version == 2
      assert v3.version == 3
    end

    test "deactivates previous versions" do
      TestStore.put(%Template{name: "test", body: "v1"})
      TestStore.put(%Template{name: "test", body: "v2"})

      {:ok, v1} = TestStore.get_version("test", 1)
      assert v1.is_active == false

      {:ok, v2} = TestStore.get_version("test", 2)
      assert v2.is_active == true
    end

    test "creates table if it doesn't exist" do
      table = :sfera_doc_test_store

      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end

      template = %Template{name: "test", body: "body"}
      assert {:ok, _} = TestStore.put(template)
      assert :ets.whereis(table) != :undefined
    end
  end

  describe "list/0" do
    setup do
      TestStore.reset()
      :ok
    end

    test "returns empty list when no templates" do
      assert {:ok, []} = TestStore.list()
    end

    test "returns only active templates" do
      TestStore.put(%Template{name: "alpha", body: "v1"})
      TestStore.put(%Template{name: "alpha", body: "v2"})
      TestStore.put(%Template{name: "bravo", body: "v1"})

      {:ok, templates} = TestStore.list()
      names_and_versions = Enum.map(templates, &{&1.name, &1.version}) |> Enum.sort()

      assert length(templates) == 2
      assert names_and_versions == [{"alpha", 2}, {"bravo", 1}]
    end
  end

  describe "list_versions/1" do
    setup do
      TestStore.reset()
      :ok
    end

    test "returns empty list for non-existent template" do
      assert {:ok, []} = TestStore.list_versions("nonexistent")
    end

    test "returns all versions sorted descending" do
      TestStore.put(%Template{name: "test", body: "v1"})
      TestStore.put(%Template{name: "test", body: "v2"})
      TestStore.put(%Template{name: "test", body: "v3"})

      {:ok, versions} = TestStore.list_versions("test")
      version_numbers = Enum.map(versions, & &1.version)

      assert version_numbers == [3, 2, 1]
    end
  end

  describe "activate_version/2" do
    setup do
      TestStore.reset()
      :ok
    end

    test "returns {:error, :not_found} for non-existent version" do
      assert {:error, :not_found} = TestStore.activate_version("test", 999)
    end

    test "activates specified version and deactivates others" do
      TestStore.put(%Template{name: "test", body: "v1"})
      TestStore.put(%Template{name: "test", body: "v2"})
      TestStore.put(%Template{name: "test", body: "v3"})

      {:ok, activated} = TestStore.activate_version("test", 2)
      assert activated.version == 2
      assert activated.is_active

      {:ok, v1} = TestStore.get_version("test", 1)
      {:ok, v2} = TestStore.get_version("test", 2)
      {:ok, v3} = TestStore.get_version("test", 3)

      assert v1.is_active == false
      assert v2.is_active == true
      assert v3.is_active == false
    end
  end

  describe "delete/1" do
    setup do
      TestStore.reset()
      :ok
    end

    test "deletes all versions of a template" do
      TestStore.put(%Template{name: "test", body: "v1"})
      TestStore.put(%Template{name: "test", body: "v2"})
      TestStore.put(%Template{name: "other", body: "v1"})

      assert :ok = TestStore.delete("test")

      assert {:error, :not_found} = TestStore.get("test")
      assert {:error, :not_found} = TestStore.get_version("test", 1)
      assert {:error, :not_found} = TestStore.get_version("test", 2)

      # Other template should still exist
      assert {:ok, _} = TestStore.get("other")
    end

    test "handles deleting non-existent template" do
      assert :ok = TestStore.delete("nonexistent")
    end
  end
end
