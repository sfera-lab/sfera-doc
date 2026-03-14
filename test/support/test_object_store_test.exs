defmodule SferaDoc.TestObjectStoreTest do
  use ExUnit.Case, async: false

  alias SferaDoc.TestObjectStore

  describe "reset/0" do
    test "handles non-existent table" do
      # Ensure table doesn't exist
      table = :sfera_doc_test_object_store

      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end

      # Reset should not crash even if table doesn't exist
      assert :ok = TestObjectStore.reset()
    end

    test "deletes existing table" do
      # Create table and add some data
      TestObjectStore.put("test", 1, "hash", "data")

      # Reset should delete the table
      assert :ok = TestObjectStore.reset()
      table = :sfera_doc_test_object_store
      assert :ets.whereis(table) == :undefined
    end
  end

  describe "worker_spec/0" do
    test "returns nil" do
      assert TestObjectStore.worker_spec() == nil
    end
  end

  describe "get/3" do
    setup do
      TestObjectStore.reset()
      :ok
    end

    test "returns :miss for non-existent object" do
      assert TestObjectStore.get("nonexistent", 1, "hash") == :miss
    end

    test "returns {:ok, binary} for existing object" do
      TestObjectStore.put("test", 1, "hash", "data")
      assert {:ok, "data"} = TestObjectStore.get("test", 1, "hash")
    end

    test "increments counter" do
      SferaDoc.TestSupport.reset_counters()
      TestObjectStore.get("test", 1, "hash")
      assert SferaDoc.TestSupport.get_counter(:object_store_get) == 1
    end
  end

  describe "put/4" do
    setup do
      TestObjectStore.reset()
      :ok
    end

    test "stores object successfully" do
      assert :ok = TestObjectStore.put("test", 1, "hash", "data")
      assert {:ok, "data"} = TestObjectStore.get("test", 1, "hash")
    end

    test "overwrites existing object" do
      TestObjectStore.put("test", 1, "hash", "old")
      TestObjectStore.put("test", 1, "hash", "new")
      assert {:ok, "new"} = TestObjectStore.get("test", 1, "hash")
    end

    test "increments counter" do
      SferaDoc.TestSupport.reset_counters()
      TestObjectStore.put("test", 1, "hash", "data")
      assert SferaDoc.TestSupport.get_counter(:object_store_put) == 1
    end

    test "creates table if it doesn't exist" do
      table = :sfera_doc_test_object_store

      if :ets.whereis(table) != :undefined do
        :ets.delete(table)
      end

      # Put should create table if needed
      assert :ok = TestObjectStore.put("test", 1, "hash", "data")
      assert :ets.whereis(table) != :undefined
    end
  end
end
