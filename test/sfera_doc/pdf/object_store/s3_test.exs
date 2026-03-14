defmodule SferaDoc.Pdf.ObjectStore.S3Test do
  use ExUnit.Case, async: false

  @moduletag :s3

  alias SferaDoc.Pdf.ObjectStore.S3

  # s3ninja accepts any credentials
  @access_key_id "AKIAIOSFODNN7EXAMPLE"
  @secret_access_key "wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
  @bucket "test-sfera-doc"
  @region "us-east-1"

  setup_all do
    # Check if s3ninja is running
    case :gen_tcp.connect(~c"localhost", 9444, [], 1000) do
      {:ok, socket} ->
        :gen_tcp.close(socket)
        :ok

      {:error, _} ->
        IO.puts("\n⚠️  s3ninja not running. Start it with:")
        IO.puts("   docker compose -f docker-compose.test.yml up -d s3ninja\n")
        ExUnit.configure(exclude: [:s3])
        :ok
    end
  end

  setup do
    # Configure ExAws to use local s3ninja endpoint
    Application.put_env(:ex_aws, :access_key_id, @access_key_id)
    Application.put_env(:ex_aws, :secret_access_key, @secret_access_key)

    Application.put_env(:ex_aws, :s3,
      scheme: "http://",
      host: "localhost",
      port: 9444,
      region: @region
    )

    # Configure S3 adapter
    Application.put_env(:sfera_doc, :pdf_object_store,
      adapter: S3,
      bucket: @bucket,
      prefix: "test/",
      ex_aws: []
    )

    # Ensure bucket exists
    ensure_bucket()

    on_exit(fn ->
      cleanup_test_objects()
    end)

    :ok
  end

  describe "s3ninja connectivity" do
    test "can create and retrieve objects directly via ExAws" do
      key = "direct-test-#{:rand.uniform(10000)}.pdf"
      test_data = "test-pdf-data-#{:rand.uniform(10000)}"

      # Put object
      req = ExAws.S3.put_object(@bucket, key, test_data)
      assert {:ok, _} = ExAws.request(req)

      # Get object
      req = ExAws.S3.get_object(@bucket, key)
      assert {:ok, %{body: ^test_data}} = ExAws.request(req)

      # Cleanup
      req = ExAws.S3.delete_object(@bucket, key)
      ExAws.request(req)
    end
  end

  describe "get/3" do
    test "returns :miss when object does not exist" do
      assert S3.get("nonexistent", 1, "hash123") == :miss
    end

    test "returns {:ok, binary} when object exists" do
      name = "test-template"
      version = 1
      hash = "abc123"
      pdf_data = "fake-pdf-binary-data-#{:rand.uniform(10000)}"

      # Put the object first
      assert :ok = S3.put(name, version, hash, pdf_data)

      # Get it back
      assert {:ok, ^pdf_data} = S3.get(name, version, hash)
    end

    test "respects the prefix configuration" do
      name = "prefixed-template"
      version = 1
      hash = "xyz789"
      pdf_data = "prefixed-pdf-data"

      assert :ok = S3.put(name, version, hash, pdf_data)
      assert {:ok, ^pdf_data} = S3.get(name, version, hash)

      # Verify the object key includes prefix
      key = "test/#{name}/#{version}/#{hash}.pdf"
      req = ExAws.S3.get_object(@bucket, key)
      assert {:ok, %{body: ^pdf_data}} = ExAws.request(req)
    end
  end

  describe "put/4" do
    test "stores object successfully" do
      name = "invoice"
      version = 2
      hash = "def456"
      pdf_data = "test-pdf-content-#{:rand.uniform(1000)}"

      assert :ok = S3.put(name, version, hash, pdf_data)

      # Verify it was stored
      assert {:ok, ^pdf_data} = S3.get(name, version, hash)
    end

    test "overwrites existing object with same key" do
      name = "receipt"
      version = 1
      hash = "same-hash"

      assert :ok = S3.put(name, version, hash, "original-data")
      assert :ok = S3.put(name, version, hash, "updated-data")

      assert {:ok, "updated-data"} = S3.get(name, version, hash)
    end

    test "stores multiple objects independently" do
      pdf1 = "pdf-one-#{:rand.uniform(1000)}"
      pdf2 = "pdf-two-#{:rand.uniform(1000)}"

      assert :ok = S3.put("doc1", 1, "hash1", pdf1)
      assert :ok = S3.put("doc2", 1, "hash2", pdf2)

      assert {:ok, ^pdf1} = S3.get("doc1", 1, "hash1")
      assert {:ok, ^pdf2} = S3.get("doc2", 1, "hash2")
    end
  end

  describe "worker_spec/0" do
    test "returns nil (no worker needed)" do
      assert S3.worker_spec() == nil
    end
  end

  describe "error handling" do
    test "handles s3 errors gracefully" do
      # Configure with invalid credentials to force errors
      Application.put_env(:ex_aws, :access_key_id, "invalid")
      Application.put_env(:ex_aws, :secret_access_key, "invalid")

      # Get should return :miss on errors (not crash)
      assert S3.get("error-test", 1, "hash") == :miss
    end

    test "handles put errors gracefully" do
      # Stop s3ninja to force connection errors
      if System.find_executable("docker") do
        System.cmd("docker", ["compose", "-f", "docker-compose.test.yml", "stop", "s3ninja"],
          stderr_to_stdout: true
        )

        # Put should return error tuple on failures
        result = S3.put("error-test", 1, "hash", "data")
        assert match?({:error, _}, result)

        # Restart s3ninja for other tests
        System.cmd("docker", ["compose", "-f", "docker-compose.test.yml", "start", "s3ninja"],
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

  defp ensure_bucket do
    req = ExAws.S3.head_bucket(@bucket)

    case ExAws.request(req) do
      {:ok, _} ->
        :ok

      {:error, {:http_error, 404, _}} ->
        # Bucket doesn't exist, create it
        req = ExAws.S3.put_bucket(@bucket, @region)

        case ExAws.request(req) do
          {:ok, _} -> :ok
          {:error, reason} -> raise "Failed to create test bucket: #{inspect(reason)}"
        end

      {:error, reason} ->
        raise "Failed to check bucket: #{inspect(reason)}"
    end
  end

  defp cleanup_test_objects do
    # List and delete all test objects with prefix
    req = ExAws.S3.list_objects(@bucket, prefix: "test/")

    case ExAws.request(req) do
      {:ok, %{body: %{contents: objects}}} ->
        Enum.each(objects, fn %{key: key} ->
          req = ExAws.S3.delete_object(@bucket, key)
          ExAws.request(req)
        end)

      _ ->
        :ok
    end
  end
end
