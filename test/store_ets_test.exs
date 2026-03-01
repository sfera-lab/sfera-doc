defmodule SferaDoc.Store.ETSTest do
  use ExUnit.Case, async: false

  @moduletag :ets

  alias SferaDoc.{Store, Template}

  setup do
    Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
    Application.put_env(:sfera_doc, :cache, enabled: false)

    case Process.whereis(SferaDoc.Store.ETS) do
      nil -> start_supervised!(SferaDoc.Store.ETS)
      _pid -> SferaDoc.Store.ETS.reset()
    end

    :ok
  end

  test "create and retrieve a template" do
    template = %Template{name: "hello", body: "Hello {{ name }}!"}
    {:ok, saved} = Store.put(template)

    assert saved.name == "hello"
    assert saved.version == 1
    assert saved.is_active == true

    {:ok, fetched} = Store.get("hello")
    assert fetched.body == "Hello {{ name }}!"
  end

  test "update creates a new version" do
    {:ok, v1} = Store.put(%Template{name: "doc", body: "v1"})
    {:ok, v2} = Store.put(%Template{name: "doc", body: "v2"})

    assert v1.version == 1
    assert v2.version == 2
    assert v2.is_active == true

    {:ok, active} = Store.get("doc")
    assert active.body == "v2"
  end

  test "get_version returns a specific version" do
    Store.put(%Template{name: "doc", body: "v1"})
    Store.put(%Template{name: "doc", body: "v2"})

    {:ok, v1} = Store.get_version("doc", 1)
    assert v1.body == "v1"
    assert v1.is_active == false
  end

  test "list returns one template per name (active version)" do
    Store.put(%Template{name: "a", body: "a"})
    Store.put(%Template{name: "a", body: "a2"})
    Store.put(%Template{name: "b", body: "b"})

    {:ok, templates} = Store.list()
    assert length(templates) == 2
    assert Enum.all?(templates, & &1.is_active)
  end

  test "list_versions returns all versions descending" do
    Store.put(%Template{name: "doc", body: "v1"})
    Store.put(%Template{name: "doc", body: "v2"})
    Store.put(%Template{name: "doc", body: "v3"})

    {:ok, versions} = Store.list_versions("doc")
    assert length(versions) == 3
    assert [v3, v2, v1] = versions
    assert v3.version == 3
    assert v2.version == 2
    assert v1.version == 1
  end

  test "activate_version switches the active version" do
    Store.put(%Template{name: "doc", body: "v1"})
    Store.put(%Template{name: "doc", body: "v2"})

    {:ok, activated} = Store.activate_version("doc", 1)
    assert activated.version == 1
    assert activated.is_active == true

    {:ok, active} = Store.get("doc")
    assert active.version == 1
  end

  test "activate_version returns :not_found for missing version" do
    Store.put(%Template{name: "doc", body: "v1"})
    assert {:error, :not_found} = Store.activate_version("doc", 99)
  end

  test "get returns :not_found for missing template" do
    assert {:error, :not_found} = Store.get("missing")
  end

  test "delete removes all versions" do
    Store.put(%Template{name: "doc", body: "v1"})
    Store.put(%Template{name: "doc", body: "v2"})

    :ok = Store.delete("doc")

    assert {:error, :not_found} = Store.get("doc")
    {:ok, []} = Store.list_versions("doc")
  end

  test "get_version returns :not_found for missing version" do
    Store.put(%Template{name: "doc", body: "v1"})
    assert {:error, :not_found} = Store.get_version("doc", 99)
  end

  test "list_versions returns empty list for unknown name" do
    {:ok, []} = Store.list_versions("nonexistent")
  end

  test "list returns empty list when store has no templates" do
    {:ok, []} = Store.list()
  end

  test "delete of non-existent name returns :ok" do
    assert :ok = Store.delete("nonexistent")
  end
end
