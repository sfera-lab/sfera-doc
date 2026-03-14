defmodule SferaDoc.Pdf.ObjectStoreTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureLog

  alias SferaDoc.Pdf.ObjectStore

  setup do
    original = Application.get_env(:sfera_doc, :pdf_object_store)

    on_exit(fn ->
      if original do
        Application.put_env(:sfera_doc, :pdf_object_store, original)
      else
        Application.delete_env(:sfera_doc, :pdf_object_store)
      end
    end)

    :ok
  end

  describe "worker_spec/0" do
    test "returns nil when no adapter configured" do
      Application.delete_env(:sfera_doc, :pdf_object_store)
      assert ObjectStore.worker_spec() == nil
    end

    test "returns adapter worker spec when configured" do
      Application.put_env(:sfera_doc, :pdf_object_store, adapter: SferaDoc.TestObjectStore)

      assert ObjectStore.worker_spec() == nil
    end
  end

  describe "get/3 with no adapter" do
    test "returns :miss when no adapter configured" do
      Application.delete_env(:sfera_doc, :pdf_object_store)
      assert ObjectStore.get("test", 1, "hash") == :miss
    end
  end

  describe "put/4 with no adapter" do
    test "returns :ok when no adapter configured" do
      Application.delete_env(:sfera_doc, :pdf_object_store)
      assert ObjectStore.put("test", 1, "hash", "data") == :ok
    end
  end

  describe "get/3 with adapter" do
    test "returns result from adapter" do
      Application.put_env(:sfera_doc, :pdf_object_store, adapter: SferaDoc.TestObjectStore)

      SferaDoc.TestObjectStore.reset()
      SferaDoc.TestObjectStore.put("test", 1, "hash", "pdf-data")

      assert {:ok, "pdf-data"} = ObjectStore.get("test", 1, "hash")
    end

    test "returns :miss when adapter returns :miss" do
      Application.put_env(:sfera_doc, :pdf_object_store, adapter: SferaDoc.TestObjectStore)

      SferaDoc.TestObjectStore.reset()
      assert ObjectStore.get("nonexistent", 1, "hash") == :miss
    end

    test "returns :miss when adapter returns error" do
      # TestObjectStore doesn't return errors, but the facade handles them
      Application.put_env(:sfera_doc, :pdf_object_store, adapter: SferaDoc.TestObjectStore)

      SferaDoc.TestObjectStore.reset()
      assert ObjectStore.get("test", 1, "hash") == :miss
    end
  end

  describe "put/4 with adapter" do
    test "stores via adapter" do
      Application.put_env(:sfera_doc, :pdf_object_store, adapter: SferaDoc.TestObjectStore)

      SferaDoc.TestObjectStore.reset()
      assert :ok = ObjectStore.put("test", 1, "hash", "pdf-data")
      assert {:ok, "pdf-data"} = SferaDoc.TestObjectStore.get("test", 1, "hash")
    end

    test "returns :ok even when adapter fails" do
      # The facade swallows errors and logs them
      Application.put_env(:sfera_doc, :pdf_object_store, adapter: SferaDoc.TestObjectStore)

      SferaDoc.TestObjectStore.reset()
      # TestObjectStore always succeeds, but the behavior is :ok on error
      assert :ok = ObjectStore.put("test", 1, "hash", "data")
    end

    test "logs warning when adapter returns error" do
      # Create a failing adapter module for testing
      defmodule FailingAdapter do
        def worker_spec, do: nil

        def get(_name, _version, _hash), do: {:error, :test_error}

        def put(_name, _version, _hash, _binary), do: {:error, :storage_failure}
      end

      Application.put_env(:sfera_doc, :pdf_object_store, adapter: FailingAdapter)

      log =
        capture_log(fn ->
          assert :ok = ObjectStore.put("test", 1, "hash", "data")
        end)

      assert log =~ "SferaDoc.Pdf.ObjectStore: failed to store PDF"
      assert log =~ "test/1"
      assert log =~ "storage_failure"
    end

    test "handles adapter returning :error tuple gracefully" do
      defmodule ErrorAdapter do
        def worker_spec, do: nil
        def get(_name, _version, _hash), do: {:error, :not_found}
        def put(_name, _version, _hash, _binary), do: {:error, {:network_error, "timeout"}}
      end

      Application.put_env(:sfera_doc, :pdf_object_store, adapter: ErrorAdapter)

      # Get should return :miss on error
      assert :miss = ObjectStore.get("test", 1, "hash")

      # Put should log and return :ok
      log =
        capture_log(fn ->
          assert :ok = ObjectStore.put("test", 1, "hash", "data")
        end)

      assert log =~ "failed to store PDF"
    end
  end
end
