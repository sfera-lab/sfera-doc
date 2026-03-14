defmodule SferaDoc.Store.ETSTest do
  use ExUnit.Case, async: false

  @moduletag :ets

  alias SferaDoc.{Store, Template}
  alias SferaDoc.Store.ETS

  setup do
    # Configure ETS store
    Application.put_env(:sfera_doc, :store, adapter: ETS)

    # Start the ETS store if not already started
    case GenServer.whereis(ETS) do
      nil ->
        {:ok, _pid} = ETS.start_link()

      _pid ->
        :ok
    end

    ETS.reset()
    :ok
  end

  describe "worker_spec/0" do
    test "returns valid worker spec" do
      spec = ETS.worker_spec()
      assert spec.id == ETS
      assert {ETS, :start_link, []} = spec.start
      assert spec.type == :worker
      assert spec.restart == :permanent
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
    end

    test "returns latest active version" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      {:ok, template} = Store.get("test")
      assert template.version == 2
      assert template.body == "v2"
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
    end

    test "creates incremental versions" do
      Store.put(%Template{name: "test", body: "v1"})
      {:ok, v2} = Store.put(%Template{name: "test", body: "v2"})
      {:ok, v3} = Store.put(%Template{name: "test", body: "v3"})

      assert v2.version == 2
      assert v3.version == 3
    end

    test "deactivates previous versions" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      {:ok, v1} = Store.get_version("test", 1)
      {:ok, v2} = Store.get_version("test", 2)

      assert v1.is_active == false
      assert v2.is_active == true
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
  end

  describe "reset/0" do
    test "clears all templates" do
      Store.put(%Template{name: "test1", body: "v1"})
      Store.put(%Template{name: "test2", body: "v1"})

      assert :ok = ETS.reset()
      assert {:ok, []} = Store.list()
    end
  end
end
