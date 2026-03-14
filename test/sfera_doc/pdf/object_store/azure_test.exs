defmodule SferaDoc.Pdf.ObjectStore.AzureTest do
  use ExUnit.Case, async: false

  @moduletag :azure

  alias SferaDoc.Pdf.ObjectStore.Azure

  # Azurite default credentials (well-known development credentials)
  @storage_account_name "devstoreaccount1"
  @storage_account_key "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="
  @container "test-sfera-doc"

  setup_all do
    # Check if Azurite is running
    case :gen_tcp.connect(~c"localhost", 10000, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _} ->
        IO.puts("\n⚠️  Azurite not running. Start it with:")
        IO.puts("   docker-compose -f docker-compose.test.yml up -d azurite\n")
        ExUnit.configure(exclude: [:azure])
        :ok
    end
  end

  setup do
    # Configure Azurex to use local Azurite endpoint
    Application.put_env(:azurex, Azurex.Blob.Config,
      storage_account_name: @storage_account_name,
      storage_account_key: @storage_account_key,
      # Use Azurite's local endpoint (must include account name in path for Azurite)
      api_url: "http://127.0.0.1:10000/#{@storage_account_name}",
      default_container: @container
    )

    # Configure Azure adapter
    Application.put_env(:sfera_doc, :pdf_object_store,
      adapter: Azure,
      container: @container,
      prefix: "test/"
    )

    # Ensure container exists
    ensure_container()

    on_exit(fn ->
      cleanup_test_blobs()
    end)

    :ok
  end

  describe "Azurite connectivity" do
    test "can create and retrieve blobs directly via Azurex" do
      blob_name = "direct-test-#{:rand.uniform(10000)}.pdf"
      test_data = "test-pdf-data-#{:rand.uniform(10000)}"

      # Put blob
      assert :ok = Azurex.Blob.put_blob(blob_name, test_data, "application/pdf", @container)

      # Get blob
      assert {:ok, ^test_data} = Azurex.Blob.get_blob(blob_name, @container)

      # Cleanup
      Azurex.Blob.delete_blob(blob_name, @container)
    end
  end

  describe "get/3" do
    test "returns :miss when blob does not exist" do
      assert Azure.get("nonexistent", 1, "hash123") == :miss
    end

    test "returns {:ok, binary} when blob exists" do
      name = "test-template"
      version = 1
      hash = "abc123"
      pdf_data = "fake-pdf-binary-data-#{:rand.uniform(10000)}"

      # Put the blob first
      assert :ok = Azure.put(name, version, hash, pdf_data)

      # Get it back
      assert {:ok, ^pdf_data} = Azure.get(name, version, hash)
    end

    test "respects the prefix configuration" do
      name = "prefixed-template"
      version = 1
      hash = "xyz789"
      pdf_data = "prefixed-pdf-data"

      assert :ok = Azure.put(name, version, hash, pdf_data)
      assert {:ok, ^pdf_data} = Azure.get(name, version, hash)

      # Verify the blob path includes prefix
      blob_name = "test/#{name}/#{version}/#{hash}.pdf"
      assert {:ok, ^pdf_data} = Azurex.Blob.get_blob(blob_name, @container)
    end
  end

  describe "put/4" do
    test "stores blob successfully" do
      name = "invoice"
      version = 2
      hash = "def456"
      pdf_data = "test-pdf-content-#{:rand.uniform(1000)}"

      assert :ok = Azure.put(name, version, hash, pdf_data)

      # Verify it was stored
      assert {:ok, ^pdf_data} = Azure.get(name, version, hash)
    end

    test "overwrites existing blob with same key" do
      name = "receipt"
      version = 1
      hash = "same-hash"

      assert :ok = Azure.put(name, version, hash, "original-data")
      assert :ok = Azure.put(name, version, hash, "updated-data")

      assert {:ok, "updated-data"} = Azure.get(name, version, hash)
    end

    test "stores multiple blobs independently" do
      pdf1 = "pdf-one-#{:rand.uniform(1000)}"
      pdf2 = "pdf-two-#{:rand.uniform(1000)}"

      assert :ok = Azure.put("doc1", 1, "hash1", pdf1)
      assert :ok = Azure.put("doc2", 1, "hash2", pdf2)

      assert {:ok, ^pdf1} = Azure.get("doc1", 1, "hash1")
      assert {:ok, ^pdf2} = Azure.get("doc2", 1, "hash2")
    end
  end

  describe "worker_spec/0" do
    test "returns nil (no worker needed)" do
      assert Azure.worker_spec() == nil
    end
  end

  describe "error handling" do
    test "handles azure errors gracefully on get" do
      # Configure with invalid endpoint to force errors (but valid base64 key)
      Application.put_env(:azurex, Azurex.Blob.Config,
        storage_account_name: "invalidaccount",
        storage_account_key: "aW52YWxpZGtleWludmFsaWRrZXk=",
        api_url: "http://127.0.0.1:99999/invalidaccount"
      )

      Application.put_env(:sfera_doc, :pdf_object_store,
        adapter: Azure,
        container: "invalid",
        prefix: "test/"
      )

      # Get should return :miss on errors (not crash)
      assert Azure.get("error-test", 1, "hash") == :miss

      # Restore valid config
      Application.put_env(:azurex, Azurex.Blob.Config,
        storage_account_name: @storage_account_name,
        storage_account_key: @storage_account_key,
        api_url: "http://127.0.0.1:10000/#{@storage_account_name}"
      )

      Application.put_env(:sfera_doc, :pdf_object_store,
        adapter: Azure,
        container: @container,
        prefix: "test/"
      )
    end

    test "handles azure errors gracefully on put" do
      # Stop azurite to force connection errors
      if System.find_executable("docker") do
        System.cmd("docker", ["compose", "-f", "docker-compose.test.yml", "stop", "azurite"],
          stderr_to_stdout: true
        )

        # Put should return error tuple on failures
        result = Azure.put("error-test", 1, "hash", "data")
        assert match?({:error, _}, result)

        # Restart azurite for other tests
        System.cmd("docker", ["compose", "-f", "docker-compose.test.yml", "start", "azurite"],
          stderr_to_stdout: true
        )

        # Wait for it to be ready
        :timer.sleep(2000)
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp ensure_container do
    case Azurex.Blob.Container.create(@container) do
      {:ok, _} -> :ok
      {:error, :already_exists} -> :ok
      {:error, reason} -> raise "Failed to create test container: #{inspect(reason)}"
    end
  end

  defp cleanup_test_blobs do
    # List and delete all test blobs with prefix
    case Azurex.Blob.list_blobs(@container, prefix: "test/") do
      {:ok, xml} ->
        # Parse blob names from XML and delete them
        # Simple regex to extract blob names (good enough for tests)
        Regex.scan(~r/<Name>(test\/[^<]+)<\/Name>/, xml)
        |> Enum.each(fn [_, blob_name] ->
          Azurex.Blob.delete_blob(blob_name, @container)
        end)

      _ ->
        :ok
    end
  end
end
