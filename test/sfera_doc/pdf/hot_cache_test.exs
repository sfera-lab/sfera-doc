defmodule SferaDoc.Pdf.HotCacheTest do
  use ExUnit.Case, async: false

  alias SferaDoc.Pdf.HotCache

  @pdf_binary <<37, 80, 68, 70>> <> String.duplicate("test pdf content", 100)

  describe "worker_spec/0 when disabled" do
    setup do
      Application.delete_env(:sfera_doc, :pdf_hot_cache)
      :ok
    end

    test "returns nil when hot cache is disabled" do
      assert HotCache.worker_spec() == nil
    end
  end

  describe "ETS backend" do
    @moduletag :ets_hot_cache

    setup do
      # Stop any running HotCache
      case GenServer.whereis(HotCache) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      # Configure ETS backend
      Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :ets, ttl: 2)

      # Start HotCache
      {:ok, _pid} = HotCache.start_link()

      on_exit(fn ->
        case GenServer.whereis(HotCache) do
          nil ->
            :ok

          pid ->
            if Process.alive?(pid) do
              GenServer.stop(pid)
            end
        end

        Application.delete_env(:sfera_doc, :pdf_hot_cache)
      end)

      :ok
    end

    test "worker_spec/0 returns valid spec for ETS" do
      spec = HotCache.worker_spec()
      assert spec.id == HotCache
      assert spec.start == {HotCache, :start_link, []}
      assert spec.type == :worker
      assert spec.restart == :permanent
    end

    test "get/3 returns :miss for non-existent entry" do
      assert :miss = HotCache.get("test", 1, "hash123")
    end

    test "put/4 and get/3 roundtrip successfully" do
      :ok = HotCache.put("test", 1, "hash123", @pdf_binary)
      assert {:ok, @pdf_binary} = HotCache.get("test", 1, "hash123")
    end

    test "different keys are isolated" do
      :ok = HotCache.put("template1", 1, "hash1", "pdf1")
      :ok = HotCache.put("template2", 1, "hash1", "pdf2")
      :ok = HotCache.put("template1", 2, "hash1", "pdf3")
      :ok = HotCache.put("template1", 1, "hash2", "pdf4")

      assert {:ok, "pdf1"} = HotCache.get("template1", 1, "hash1")
      assert {:ok, "pdf2"} = HotCache.get("template2", 1, "hash1")
      assert {:ok, "pdf3"} = HotCache.get("template1", 2, "hash1")
      assert {:ok, "pdf4"} = HotCache.get("template1", 1, "hash2")
    end

    test "entries expire after TTL" do
      :ok = HotCache.put("test", 1, "hash123", @pdf_binary)
      assert {:ok, @pdf_binary} = HotCache.get("test", 1, "hash123")

      # Wait for TTL to expire (configured to 2 seconds)
      Process.sleep(2100)

      assert :miss = HotCache.get("test", 1, "hash123")
    end

    test "sweep mechanism removes expired entries" do
      :ok = HotCache.put("test", 1, "hash123", @pdf_binary)

      # Wait for TTL to expire and sweep to run
      Process.sleep(2500)

      # Trigger sweep by sending message
      send(HotCache, :sweep)
      Process.sleep(100)

      # Entry should be gone
      assert :miss = HotCache.get("test", 1, "hash123")
    end

    test "fresh entries remain after sweep" do
      :ok = HotCache.put("test", 1, "hash123", @pdf_binary)

      # Trigger sweep immediately (entry is fresh)
      send(HotCache, :sweep)
      Process.sleep(100)

      # Entry should still be there
      assert {:ok, @pdf_binary} = HotCache.get("test", 1, "hash123")
    end

    test "handles large PDF binaries" do
      large_pdf = String.duplicate("PDF", 100_000)
      :ok = HotCache.put("large", 1, "hash", large_pdf)
      assert {:ok, ^large_pdf} = HotCache.get("large", 1, "hash")
    end

    test "handles concurrent reads and writes" do
      tasks =
        for i <- 1..10 do
          Task.async(fn ->
            :ok = HotCache.put("concurrent", i, "hash#{i}", "pdf#{i}")
            {:ok, _} = HotCache.get("concurrent", i, "hash#{i}")
          end)
        end

      Enum.each(tasks, &Task.await/1)

      # Verify all entries are present
      for i <- 1..10 do
        expected = "pdf#{i}"
        assert {:ok, ^expected} = HotCache.get("concurrent", i, "hash#{i}")
      end
    end
  end

  describe "Redis backend" do
    @moduletag :redis_hot_cache

    setup do
      # Stop any running processes with conflicting names
      for name <- [HotCache] do
        case GenServer.whereis(name) do
          nil -> :ok
          pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
        end
      end

      # Wait a moment for processes to fully terminate
      Process.sleep(50)

      # Start a separate Redis connection for test verification
      redis_opts = [host: "localhost", port: 6379]
      {:ok, conn} = Redix.start_link(redis_opts)

      # Clear Redis
      Redix.command!(conn, ["FLUSHDB"])

      # Configure Redis backend
      Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :redis, ttl: 2)
      Application.put_env(:sfera_doc, :redis, host: "localhost", port: 6379)

      # Start HotCache (it will start its own named Redis connection)
      {:ok, _pid} = HotCache.start_link()

      on_exit(fn ->
        # Stop HotCache GenServer
        case GenServer.whereis(HotCache) do
          nil -> :ok
          pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
        end

        # Also stop the Redix connection that HotCache started
        case Process.whereis(HotCache.redis_conn_name()) do
          nil -> :ok
          pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
        end

        # Small delay to ensure cleanup completes
        Process.sleep(100)

        Application.delete_env(:sfera_doc, :pdf_hot_cache)
        Application.delete_env(:sfera_doc, :redis)
      end)

      %{conn: conn}
    end

    test "worker_spec/0 returns valid spec for Redis" do
      spec = HotCache.worker_spec()
      assert spec.id == HotCache
      assert spec.start == {HotCache, :start_link, []}
      assert spec.type == :worker
      assert spec.restart == :permanent
    end

    test "get/3 returns :miss for non-existent entry" do
      assert :miss = HotCache.get("test", 1, "hash123")
    end

    test "put/4 and get/3 roundtrip successfully" do
      :ok = HotCache.put("test", 1, "hash123", @pdf_binary)
      assert {:ok, @pdf_binary} = HotCache.get("test", 1, "hash123")
    end

    test "different keys are isolated" do
      :ok = HotCache.put("template1", 1, "hash1", "pdf1")
      :ok = HotCache.put("template2", 1, "hash1", "pdf2")
      :ok = HotCache.put("template1", 2, "hash1", "pdf3")
      :ok = HotCache.put("template1", 1, "hash2", "pdf4")

      assert {:ok, "pdf1"} = HotCache.get("template1", 1, "hash1")
      assert {:ok, "pdf2"} = HotCache.get("template2", 1, "hash1")
      assert {:ok, "pdf3"} = HotCache.get("template1", 2, "hash1")
      assert {:ok, "pdf4"} = HotCache.get("template1", 1, "hash2")
    end

    test "entries expire after TTL (Redis native expiration)" do
      :ok = HotCache.put("test", 1, "hash123", @pdf_binary)
      assert {:ok, @pdf_binary} = HotCache.get("test", 1, "hash123")

      # Wait for Redis TTL to expire (configured to 2 seconds)
      Process.sleep(2100)

      assert :miss = HotCache.get("test", 1, "hash123")
    end

    test "verifies Redis key format", %{conn: conn} do
      :ok = HotCache.put("mytemplate", 5, "abc123", @pdf_binary)

      # Check the key exists with the expected format
      key = "sfera_doc:pdf:mytemplate:5:abc123"
      assert {:ok, @pdf_binary} = Redix.command(conn, ["GET", key])
    end

    test "verifies Redis TTL is set", %{conn: conn} do
      :ok = HotCache.put("test", 1, "hash", @pdf_binary)

      key = "sfera_doc:pdf:test:1:hash"
      {:ok, ttl} = Redix.command(conn, ["TTL", key])

      # TTL should be around 2 seconds (within a small margin)
      assert ttl >= 1 and ttl <= 2
    end

    test "handles large PDF binaries" do
      large_pdf = String.duplicate("PDF", 100_000)
      :ok = HotCache.put("large", 1, "hash", large_pdf)
      assert {:ok, ^large_pdf} = HotCache.get("large", 1, "hash")
    end

    test "handles Redis errors gracefully (returns :miss on get failure)" do
      import ExUnit.CaptureLog

      # Stop Redis connection to simulate failure
      case Process.whereis(HotCache.redis_conn_name()) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      log =
        capture_log(fn ->
          assert :miss = HotCache.get("test", 1, "hash")
        end)

      assert log =~ "Redis get failed"
    end

    test "handles Redis errors gracefully (returns :ok on put failure)" do
      import ExUnit.CaptureLog

      # Stop Redis connection to simulate failure
      case Process.whereis(HotCache.redis_conn_name()) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      log =
        capture_log(fn ->
          assert :ok = HotCache.put("test", 1, "hash", @pdf_binary)
        end)

      assert log =~ "Redis put failed"
    end
  end

  describe "disabled backend" do
    setup do
      Application.delete_env(:sfera_doc, :pdf_hot_cache)
      :ok
    end

    test "get/3 always returns :miss when disabled" do
      assert :miss = HotCache.get("test", 1, "hash")
    end

    test "put/4 is a no-op when disabled" do
      assert :ok = HotCache.put("test", 1, "hash", @pdf_binary)
      assert :miss = HotCache.get("test", 1, "hash")
    end
  end

  describe "GenServer message handling" do
    @moduletag :ets_hot_cache

    setup do
      case GenServer.whereis(HotCache) do
        nil -> :ok
        pid -> GenServer.stop(pid)
      end

      Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :ets, ttl: 2)
      {:ok, _pid} = HotCache.start_link()

      on_exit(fn ->
        case GenServer.whereis(HotCache) do
          nil -> :ok
          pid -> if Process.alive?(pid), do: GenServer.stop(pid)
        end

        Application.delete_env(:sfera_doc, :pdf_hot_cache)
      end)

      :ok
    end

    test "handles unknown messages gracefully" do
      # Send an unexpected message to the GenServer
      send(HotCache, :unknown_message)
      send(HotCache, {:unexpected, :tuple})
      send(HotCache, %{random: "map"})

      # Wait a bit to ensure messages are processed
      Process.sleep(100)

      # Verify the GenServer is still alive and functional
      assert Process.alive?(Process.whereis(HotCache))
      assert :ok = HotCache.put("test", 1, "hash", @pdf_binary)
      assert {:ok, @pdf_binary} = HotCache.get("test", 1, "hash")
    end

    test "continues working after receiving unknown messages during sweep" do
      :ok = HotCache.put("test", 1, "hash", @pdf_binary)

      # Send unknown message along with sweep
      send(HotCache, :random_message)
      send(HotCache, :sweep)

      Process.sleep(100)

      # Should still work
      assert {:ok, @pdf_binary} = HotCache.get("test", 1, "hash")
    end
  end

  describe "Redis configuration normalization" do
    test "normalizes string URL configuration" do
      # Test the normalize_redis_opts function indirectly
      # by setting up Redis with string URL
      case GenServer.whereis(HotCache) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      redis_url = "redis://localhost:6379"
      Application.put_env(:sfera_doc, :redis, redis_url)
      Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :redis, ttl: 2)

      # This should work with string URL
      {:ok, _pid} = HotCache.start_link()

      # Ensure a clean Redis state for the assertion
      Redix.command(HotCache.redis_conn_name(), ["FLUSHDB"])

      # Verify it works
      assert :miss = HotCache.get("test", 1, "hash")

      # Cleanup
      case GenServer.whereis(HotCache) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      case Process.whereis(HotCache.redis_conn_name()) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      Application.delete_env(:sfera_doc, :redis)
      Application.delete_env(:sfera_doc, :pdf_hot_cache)
    end

    test "normalizes keyword list configuration" do
      case GenServer.whereis(HotCache) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      redis_opts = [host: "localhost", port: 6379]
      Application.put_env(:sfera_doc, :redis, redis_opts)
      Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :redis, ttl: 2)

      # This should work with keyword list
      {:ok, _pid} = HotCache.start_link()

      # Ensure a clean Redis state for the assertion
      Redix.command(HotCache.redis_conn_name(), ["FLUSHDB"])

      # Verify it works
      assert :miss = HotCache.get("test", 1, "hash")

      # Cleanup
      case GenServer.whereis(HotCache) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      case Process.whereis(HotCache.redis_conn_name()) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      Application.delete_env(:sfera_doc, :redis)
      Application.delete_env(:sfera_doc, :pdf_hot_cache)
    end

    test "uses hot_cache-specific redis config when provided" do
      case GenServer.whereis(HotCache) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      # Set different configs
      Application.put_env(:sfera_doc, :redis, host: "wrong", port: 1234)

      Application.put_env(:sfera_doc, :pdf_hot_cache,
        adapter: :redis,
        ttl: 2,
        redis: [host: "localhost", port: 6379]
      )

      # Should use the hot_cache-specific redis config
      {:ok, _pid} = HotCache.start_link()

      # Ensure a clean Redis state for the assertion
      Redix.command(HotCache.redis_conn_name(), ["FLUSHDB"])

      # Verify it works
      assert :miss = HotCache.get("test", 1, "hash")

      # Cleanup
      case GenServer.whereis(HotCache) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      case Process.whereis(HotCache.redis_conn_name()) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      Application.delete_env(:sfera_doc, :redis)
      Application.delete_env(:sfera_doc, :pdf_hot_cache)
    end

    test "uses hot_cache-specific redis URL when provided" do
      case GenServer.whereis(HotCache) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      # Set different configs
      Application.put_env(:sfera_doc, :redis, host: "wrong", port: 1234)

      Application.put_env(:sfera_doc, :pdf_hot_cache,
        adapter: :redis,
        ttl: 2,
        redis: "redis://localhost:6379"
      )

      # Should use the hot_cache-specific redis URL
      {:ok, _pid} = HotCache.start_link()

      # Ensure a clean Redis state for the assertion
      Redix.command(HotCache.redis_conn_name(), ["FLUSHDB"])

      # Verify it works
      assert :miss = HotCache.get("test", 1, "hash")

      # Cleanup
      case GenServer.whereis(HotCache) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      case Process.whereis(HotCache.redis_conn_name()) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1000)
      end

      Application.delete_env(:sfera_doc, :redis)
      Application.delete_env(:sfera_doc, :pdf_hot_cache)
    end
  end
end
