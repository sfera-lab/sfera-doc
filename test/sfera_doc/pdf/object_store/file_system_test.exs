defmodule SferaDoc.Pdf.ObjectStore.FileSystemTest do
  use ExUnit.Case, async: false

  @moduletag :file_system

  alias SferaDoc.Pdf.ObjectStore.FileSystem

  @test_base_path "/tmp/sfera_doc_test_#{System.system_time()}"

  setup do
    # Configure FileSystem adapter with test path
    Application.put_env(:sfera_doc, :pdf_object_store,
      adapter: FileSystem,
      path: @test_base_path,
      prefix: "test/"
    )

    on_exit(fn ->
      # Cleanup test directory
      File.rm_rf(@test_base_path)
    end)

    :ok
  end

  describe "get/3" do
    test "returns :miss when file does not exist" do
      assert FileSystem.get("nonexistent", 1, "hash123") == :miss
    end

    test "returns {:ok, binary} when file exists" do
      name = "test-template"
      version = 1
      hash = "abc123"
      pdf_data = "fake-pdf-binary-data-#{:rand.uniform(10000)}"

      # Put the file first
      assert :ok = FileSystem.put(name, version, hash, pdf_data)

      # Get it back
      assert {:ok, ^pdf_data} = FileSystem.get(name, version, hash)
    end

    test "returns :miss when file is corrupted/unreadable" do
      name = "corrupted"
      version = 1
      hash = "bad"

      # Create the directory structure
      path = Path.join([@test_base_path, "test/corrupted", "1", "bad.pdf"])
      File.mkdir_p!(Path.dirname(path))

      # Create a file with restrictive permissions (if not on Windows)
      if :os.type() != {:win32, :nt} do
        File.write!(path, "data")
        File.chmod!(path, 0o000)

        assert FileSystem.get(name, version, hash) == :miss

        # Cleanup - restore permissions so we can delete it
        File.chmod!(path, 0o644)
      end
    end

    test "handles different versions of the same template" do
      name = "versioned"
      hash = "samehash"
      v1_data = "version-1-data"
      v2_data = "version-2-data"

      assert :ok = FileSystem.put(name, 1, hash, v1_data)
      assert :ok = FileSystem.put(name, 2, hash, v2_data)

      assert {:ok, ^v1_data} = FileSystem.get(name, 1, hash)
      assert {:ok, ^v2_data} = FileSystem.get(name, 2, hash)
    end
  end

  describe "put/4" do
    test "stores file successfully" do
      name = "invoice"
      version = 2
      hash = "def456"
      pdf_data = "test-pdf-content-#{:rand.uniform(1000)}"

      assert :ok = FileSystem.put(name, version, hash, pdf_data)

      # Verify it was stored
      assert {:ok, ^pdf_data} = FileSystem.get(name, version, hash)
    end

    test "overwrites existing file with same key" do
      name = "receipt"
      version = 1
      hash = "same-hash"

      assert :ok = FileSystem.put(name, version, hash, "original-data")
      assert :ok = FileSystem.put(name, version, hash, "updated-data")

      assert {:ok, "updated-data"} = FileSystem.get(name, version, hash)
    end

    test "stores multiple files independently" do
      pdf1 = "pdf-one-#{:rand.uniform(1000)}"
      pdf2 = "pdf-two-#{:rand.uniform(1000)}"

      assert :ok = FileSystem.put("doc1", 1, "hash1", pdf1)
      assert :ok = FileSystem.put("doc2", 1, "hash2", pdf2)

      assert {:ok, ^pdf1} = FileSystem.get("doc1", 1, "hash1")
      assert {:ok, ^pdf2} = FileSystem.get("doc2", 1, "hash2")
    end

    test "creates necessary directory structure" do
      name = "deep/nested/template"
      version = 1
      hash = "xyz789"
      pdf_data = "nested-pdf-data"

      assert :ok = FileSystem.put(name, version, hash, pdf_data)
      assert {:ok, ^pdf_data} = FileSystem.get(name, version, hash)

      # Verify directory structure exists
      expected_path = Path.join([@test_base_path, "test/deep/nested/template", "1", "xyz789.pdf"])
      assert File.exists?(expected_path)
    end

    test "respects the prefix configuration" do
      name = "prefixed-template"
      version = 1
      hash = "prefix123"
      pdf_data = "prefixed-pdf-data"

      assert :ok = FileSystem.put(name, version, hash, pdf_data)

      # Verify the file path includes prefix
      expected_path = Path.join([@test_base_path, "test/prefixed-template", "1", "prefix123.pdf"])
      assert File.exists?(expected_path)
      assert {:ok, ^pdf_data} = File.read(expected_path)
    end

    test "handles binary data correctly" do
      name = "binary-test"
      version = 1
      hash = "bin123"
      # Create some binary data that's not UTF-8 text
      pdf_data = <<0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x10, 0x4A, 0x46>>

      assert :ok = FileSystem.put(name, version, hash, pdf_data)
      assert {:ok, ^pdf_data} = FileSystem.get(name, version, hash)
    end

    test "handles large files" do
      name = "large-file"
      version = 1
      hash = "large123"
      # Create a 1MB file
      pdf_data = String.duplicate("A", 1_024_000)

      assert :ok = FileSystem.put(name, version, hash, pdf_data)
      assert {:ok, ^pdf_data} = FileSystem.get(name, version, hash)
    end
  end

  describe "worker_spec/0" do
    test "returns nil (no worker needed)" do
      assert FileSystem.worker_spec() == nil
    end
  end

  describe "file organization" do
    test "organizes files by name/version/hash structure" do
      # Store multiple files
      FileSystem.put("invoice", 1, "hash1", "data1")
      FileSystem.put("invoice", 1, "hash2", "data2")
      FileSystem.put("invoice", 2, "hash1", "data3")
      FileSystem.put("receipt", 1, "hash1", "data4")

      # Verify directory structure
      assert File.dir?(Path.join(@test_base_path, "test/invoice"))
      assert File.dir?(Path.join(@test_base_path, "test/invoice/1"))
      assert File.dir?(Path.join(@test_base_path, "test/invoice/2"))
      assert File.dir?(Path.join(@test_base_path, "test/receipt"))
      assert File.dir?(Path.join(@test_base_path, "test/receipt/1"))

      # Verify files exist
      assert File.exists?(Path.join(@test_base_path, "test/invoice/1/hash1.pdf"))
      assert File.exists?(Path.join(@test_base_path, "test/invoice/1/hash2.pdf"))
      assert File.exists?(Path.join(@test_base_path, "test/invoice/2/hash1.pdf"))
      assert File.exists?(Path.join(@test_base_path, "test/receipt/1/hash1.pdf"))
    end

    test "handles templates with special characters in names" do
      # Test with URL-safe but uncommon characters
      name = "template-name_with.special+chars"
      version = 1
      hash = "special123"
      pdf_data = "special-data"

      assert :ok = FileSystem.put(name, version, hash, pdf_data)
      assert {:ok, ^pdf_data} = FileSystem.get(name, version, hash)
    end
  end

  describe "configuration without prefix" do
    test "works correctly without prefix configuration" do
      # Reconfigure without prefix
      Application.put_env(:sfera_doc, :pdf_object_store,
        adapter: FileSystem,
        path: @test_base_path
      )

      name = "no-prefix"
      version = 1
      hash = "noprefix123"
      pdf_data = "no-prefix-data"

      assert :ok = FileSystem.put(name, version, hash, pdf_data)

      # Verify file is at root level (no prefix)
      expected_path = Path.join([@test_base_path, "no-prefix", "1", "noprefix123.pdf"])
      assert File.exists?(expected_path)
      assert {:ok, ^pdf_data} = FileSystem.get(name, version, hash)
    end
  end

  describe "error handling" do
    test "handles write errors gracefully" do
      if :os.type() != {:win32, :nt} do
        # Create a read-only directory to force write errors
        readonly_path = "/tmp/sfera_doc_readonly_#{System.system_time()}"
        File.mkdir_p!(readonly_path)
        File.chmod!(readonly_path, 0o444)

        Application.put_env(:sfera_doc, :pdf_object_store,
          adapter: FileSystem,
          path: readonly_path
        )

        # Put should return error tuple when write fails
        result = FileSystem.put("test", 1, "hash", "data")
        assert match?({:error, _}, result)

        # Cleanup
        File.chmod!(readonly_path, 0o755)
        File.rm_rf!(readonly_path)

        # Restore config
        Application.put_env(:sfera_doc, :pdf_object_store,
          adapter: FileSystem,
          path: @test_base_path,
          prefix: "test/"
        )
      end
    end

    test "handles read errors for other reasons" do
      # This is already partially tested by the corrupted file test
      # but let's ensure we cover the warning path
      if :os.type() != {:win32, :nt} do
        name = "read-error"
        version = 1
        hash = "error"

        path = Path.join([@test_base_path, "test/read-error", "1", "error.pdf"])
        File.mkdir_p!(Path.dirname(path))
        File.write!(path, "data")
        File.chmod!(path, 0o000)

        assert FileSystem.get(name, version, hash) == :miss

        # Cleanup
        File.chmod!(path, 0o644)
      end
    end
  end
end
