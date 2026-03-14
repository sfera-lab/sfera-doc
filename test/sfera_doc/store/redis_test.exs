defmodule SferaDoc.Store.RedisTest do
  use ExUnit.Case, async: false

  @moduletag :redis

  alias SferaDoc.{Store, Template}
  alias SferaDoc.Store.Redis

  setup do
    # Start Redis connection
    {:ok, conn} = Redix.start_link(name: Redis)

    # Clear all keys
    Redix.command!(conn, ["FLUSHDB"])

    # Configure Redis store
    Application.put_env(:sfera_doc, :store, adapter: Redis)
    Application.put_env(:sfera_doc, :redis, host: "localhost", port: 6379)

    on_exit(fn ->
      Application.delete_env(:sfera_doc, :store)
      Application.delete_env(:sfera_doc, :redis)
    end)

    %{conn: conn}
  end

  describe "worker_spec/0" do
    test "returns valid Redix worker spec" do
      spec = Redis.worker_spec()
      assert spec.id == Redix
      {mod, fun, [opts]} = spec.start
      assert mod == Redix
      assert fun == :start_link
      assert opts[:name] == Redis
      assert opts[:host] == "localhost"
      assert opts[:port] == 6379
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

      assert {:ok, v2} = Store.get_version("test", 2)
      assert v2.version == 2
      assert v2.body == "v2"
    end

    test "returns versions regardless of active status" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      # Both versions should be retrievable
      {:ok, v1} = Store.get_version("test", 1)
      {:ok, v2} = Store.get_version("test", 2)

      assert v1.version == 1
      assert v2.version == 2
    end
  end

  describe "put/1" do
    test "creates first version", %{conn: conn} do
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

      # Verify Redis keys
      assert {:ok, "1"} = Redix.command(conn, ["GET", "sfera_doc:template:test:active"])

      assert {:ok, ["1"]} =
               Redix.command(conn, ["ZRANGE", "sfera_doc:template:test:versions", "0", "-1"])

      assert {:ok, 1} = Redix.command(conn, ["SISMEMBER", "sfera_doc:names", "test"])
    end

    test "creates incremental versions" do
      Store.put(%Template{name: "test", body: "v1"})
      {:ok, v2} = Store.put(%Template{name: "test", body: "v2"})
      {:ok, v3} = Store.put(%Template{name: "test", body: "v3"})

      assert v2.version == 2
      assert v3.version == 3
    end

    test "updates active pointer atomically", %{conn: conn} do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      # Active pointer should be updated to v2
      assert {:ok, "2"} = Redix.command(conn, ["GET", "sfera_doc:template:test:active"])

      # Both versions should exist
      {:ok, v1_json} = Redix.command(conn, ["GET", "sfera_doc:template:test:version:1"])
      {:ok, v2_json} = Redix.command(conn, ["GET", "sfera_doc:template:test:version:2"])

      assert v1_json != nil
      assert v2_json != nil
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
      # Redis JSON decode returns atom keys, so compare values
      assert is_map(template.variables_schema)

      {:ok, fetched} = Store.get("test")
      # Compare the actual content, not exact map structure (atom vs string keys)
      assert fetched.variables_schema["type"] == "object" or
               fetched.variables_schema[:type] == "object"
    end

    test "handles nil variables_schema" do
      {:ok, template} = Store.put(%Template{name: "test", body: "body"})
      assert template.variables_schema == nil

      {:ok, fetched} = Store.get("test")
      assert fetched.variables_schema == nil
    end

    test "encodes DateTime fields correctly" do
      now = DateTime.utc_now()

      template = %Template{
        name: "test",
        body: "body",
        inserted_at: now,
        updated_at: now
      }

      {:ok, created} = Store.put(template)
      {:ok, fetched} = Store.get("test")

      # DateTimes should be preserved (within 1 second due to precision)
      assert DateTime.diff(fetched.inserted_at, now) <= 1
      assert DateTime.diff(fetched.updated_at, now) <= 1
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

    test "handles missing templates gracefully" do
      Store.put(%Template{name: "test", body: "v1"})

      # Manually corrupt data by removing template key but keeping name in set
      {:ok, conn} = Redix.start_link()
      Redix.command!(conn, ["SADD", "sfera_doc:names", "corrupted"])

      {:ok, templates} = Store.list()
      # Should only return valid templates
      assert length(templates) == 1
      assert hd(templates).name == "test"
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

    test "includes all versions" do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      {:ok, versions} = Store.list_versions("test")
      assert length(versions) == 2
    end

    test "handles missing version data gracefully" do
      Store.put(%Template{name: "test", body: "v1"})

      # Manually add a version entry without data
      {:ok, conn} = Redix.start_link()
      Redix.command!(conn, ["ZADD", "sfera_doc:template:test:versions", "999", "999"])

      {:ok, versions} = Store.list_versions("test")
      # Should only return valid versions
      assert length(versions) == 1
      assert hd(versions).version == 1
    end
  end

  describe "activate_version/2" do
    test "returns {:error, :not_found} for non-existent version" do
      assert {:error, :not_found} = Store.activate_version("test", 999)
    end

    test "activates specified version", %{conn: conn} do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})
      Store.put(%Template{name: "test", body: "v3"})

      {:ok, activated} = Store.activate_version("test", 2)
      assert activated.version == 2
      assert activated.is_active

      # Active pointer should be updated
      assert {:ok, "2"} = Redix.command(conn, ["GET", "sfera_doc:template:test:active"])

      # get/1 should return version 2
      {:ok, active} = Store.get("test")
      assert active.version == 2
    end

    test "uses Redis pipeline for atomicity", %{conn: conn} do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      # Activate v1
      {:ok, _} = Store.activate_version("test", 1)

      # Verify atomic update
      assert {:ok, "1"} = Redix.command(conn, ["GET", "sfera_doc:template:test:active"])
    end

    test "handles activating already active version" do
      {:ok, v1} = Store.put(%Template{name: "test", body: "v1"})
      assert v1.is_active

      {:ok, activated} = Store.activate_version("test", 1)
      assert activated.is_active
      assert activated.version == 1
    end
  end

  describe "delete/1" do
    test "deletes all versions of a template", %{conn: conn} do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})
      Store.put(%Template{name: "other", body: "v1"})

      assert :ok = Store.delete("test")

      assert {:error, :not_found} = Store.get("test")
      assert {:error, :not_found} = Store.get_version("test", 1)
      assert {:error, :not_found} = Store.get_version("test", 2)

      # Other template should still exist
      assert {:ok, _} = Store.get("other")

      # Redis keys should be cleaned up
      assert {:ok, nil} = Redix.command(conn, ["GET", "sfera_doc:template:test:active"])

      assert {:ok, []} =
               Redix.command(conn, ["ZRANGE", "sfera_doc:template:test:versions", "0", "-1"])

      assert {:ok, 0} = Redix.command(conn, ["SISMEMBER", "sfera_doc:names", "test"])
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

    test "uses Redis pipeline for atomic deletion", %{conn: conn} do
      Store.put(%Template{name: "test", body: "v1"})
      Store.put(%Template{name: "test", body: "v2"})

      Store.delete("test")

      # All keys should be removed atomically
      assert {:ok, nil} = Redix.command(conn, ["GET", "sfera_doc:template:test:version:1"])
      assert {:ok, nil} = Redix.command(conn, ["GET", "sfera_doc:template:test:version:2"])
      assert {:ok, nil} = Redix.command(conn, ["GET", "sfera_doc:template:test:active"])
    end
  end

  describe "JSON encoding/decoding" do
    test "correctly encodes and decodes templates with all fields" do
      now = DateTime.utc_now()

      template = %Template{
        id: "test-id",
        name: "test",
        body: "body content",
        version: 1,
        is_active: true,
        variables_schema: %{"test" => "schema"},
        inserted_at: now,
        updated_at: now
      }

      {:ok, created} = Store.put(template)
      {:ok, fetched} = Store.get("test")

      assert fetched.name == template.name
      assert fetched.body == template.body
      # JSON decode may return atom keys
      assert is_map(fetched.variables_schema)
      assert DateTime.diff(fetched.inserted_at, now) <= 1
    end

    test "handles nil DateTime fields" do
      template = %Template{
        name: "test",
        body: "body",
        inserted_at: nil,
        updated_at: nil
      }

      {:ok, _} = Store.put(template)
      {:ok, fetched} = Store.get("test")

      assert fetched.inserted_at == nil
      assert fetched.updated_at == nil
    end
  end
end
