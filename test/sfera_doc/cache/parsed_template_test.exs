defmodule SferaDoc.Cache.ParsedTemplateTest do
  use ExUnit.Case, async: false

  alias SferaDoc.Cache.ParsedTemplate

  @sample_ast {:template, [children: [{:text, "Hello"}]]}

  setup do
    # Stop any running ParsedTemplate
    case GenServer.whereis(ParsedTemplate) do
      nil -> :ok
      pid -> GenServer.stop(pid)
    end

    # Store original config
    original_config = Application.get_env(:sfera_doc, :cache)

    on_exit(fn ->
      case GenServer.whereis(ParsedTemplate) do
        nil -> :ok
        pid -> if Process.alive?(pid), do: GenServer.stop(pid)
      end

      if original_config do
        Application.put_env(:sfera_doc, :cache, original_config)
      else
        Application.delete_env(:sfera_doc, :cache)
      end
    end)

    {:ok, original_config: original_config}
  end

  describe "worker_spec/0 when cache is enabled" do
    test "returns valid worker spec" do
      Application.put_env(:sfera_doc, :cache, enabled: true)

      spec = ParsedTemplate.worker_spec()
      assert spec.id == ParsedTemplate
      assert spec.start == {ParsedTemplate, :start_link, []}
      assert spec.type == :worker
      assert spec.restart == :permanent
    end
  end

  describe "worker_spec/0 when cache is disabled" do
    test "returns nil" do
      Application.put_env(:sfera_doc, :cache, enabled: false)

      assert ParsedTemplate.worker_spec() == nil
    end
  end

  describe "get/2 and put/3 when cache is enabled" do
    setup do
      Application.put_env(:sfera_doc, :cache, enabled: true, ttl: 2)

      case ParsedTemplate.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      :ok
    end

    test "get/2 returns :miss for non-existent entry" do
      assert :miss = ParsedTemplate.get("test", 1)
    end

    test "put/3 and get/2 roundtrip successfully" do
      :ok = ParsedTemplate.put("test", 1, @sample_ast)
      assert {:ok, @sample_ast} = ParsedTemplate.get("test", 1)
    end

    test "different templates and versions are isolated" do
      ast1 = {:template, [children: [{:text, "AST1"}]]}
      ast2 = {:template, [children: [{:text, "AST2"}]]}
      ast3 = {:template, [children: [{:text, "AST3"}]]}

      :ok = ParsedTemplate.put("template1", 1, ast1)
      :ok = ParsedTemplate.put("template2", 1, ast2)
      :ok = ParsedTemplate.put("template1", 2, ast3)

      assert {:ok, ^ast1} = ParsedTemplate.get("template1", 1)
      assert {:ok, ^ast2} = ParsedTemplate.get("template2", 1)
      assert {:ok, ^ast3} = ParsedTemplate.get("template1", 2)
    end

    test "entries expire after TTL" do
      :ok = ParsedTemplate.put("test", 1, @sample_ast)
      assert {:ok, @sample_ast} = ParsedTemplate.get("test", 1)

      # Wait for TTL to expire (configured to 2 seconds)
      Process.sleep(2100)

      assert :miss = ParsedTemplate.get("test", 1)
    end

    test "fresh entries remain valid before TTL" do
      :ok = ParsedTemplate.put("test", 1, @sample_ast)

      # Read immediately
      assert {:ok, @sample_ast} = ParsedTemplate.get("test", 1)

      # Wait less than TTL
      Process.sleep(500)

      # Should still be there
      assert {:ok, @sample_ast} = ParsedTemplate.get("test", 1)
    end

    test "handles complex AST structures" do
      complex_ast =
        {:template,
         [
           children: [
             {:tag, :for, [variable: "item", collection: "items"],
              [children: [{:text, "Item: "}, {:variable, "item"}]]},
             {:tag, :if, [condition: "show"], [children: [{:text, "Visible"}]]}
           ]
         ]}

      :ok = ParsedTemplate.put("complex", 1, complex_ast)
      assert {:ok, ^complex_ast} = ParsedTemplate.get("complex", 1)
    end

    test "handles concurrent reads" do
      :ok = ParsedTemplate.put("concurrent", 1, @sample_ast)

      tasks =
        for _i <- 1..100 do
          Task.async(fn ->
            {:ok, @sample_ast} = ParsedTemplate.get("concurrent", 1)
          end)
        end

      Enum.each(tasks, &Task.await/1)
    end

    test "handles concurrent writes" do
      tasks =
        for i <- 1..20 do
          Task.async(fn ->
            ast = {:template, [children: [{:text, "AST#{i}"}]]}
            :ok = ParsedTemplate.put("template#{i}", 1, ast)
          end)
        end

      Enum.each(tasks, &Task.await/1)

      # Verify all entries were written
      for i <- 1..20 do
        result = ParsedTemplate.get("template#{i}", 1)
        assert {:ok, _ast} = result
      end
    end

    test "put/3 overwrites existing entry" do
      ast1 = {:template, [children: [{:text, "Version 1"}]]}
      ast2 = {:template, [children: [{:text, "Version 2"}]]}

      :ok = ParsedTemplate.put("test", 1, ast1)
      assert {:ok, ^ast1} = ParsedTemplate.get("test", 1)

      # Overwrite with new AST
      :ok = ParsedTemplate.put("test", 1, ast2)
      assert {:ok, ^ast2} = ParsedTemplate.get("test", 1)
    end

    test "put/3 resets TTL" do
      :ok = ParsedTemplate.put("test", 1, @sample_ast)

      # Wait almost to expiry
      Process.sleep(1500)

      # Put again (resets TTL)
      :ok = ParsedTemplate.put("test", 1, @sample_ast)

      # Wait another 1 second (total 2.5s, but TTL was reset after 1.5s)
      Process.sleep(1000)

      # Should still be valid
      assert {:ok, @sample_ast} = ParsedTemplate.get("test", 1)
    end
  end

  describe "invalidate/2 when cache is enabled" do
    setup do
      Application.put_env(:sfera_doc, :cache, enabled: true, ttl: 300)

      case ParsedTemplate.start_link() do
        {:ok, _pid} -> :ok
        {:error, {:already_started, _pid}} -> :ok
      end

      :ok
    end

    test "removes entry from cache" do
      :ok = ParsedTemplate.put("test", 1, @sample_ast)
      assert {:ok, @sample_ast} = ParsedTemplate.get("test", 1)

      :ok = ParsedTemplate.invalidate("test", 1)
      assert :miss = ParsedTemplate.get("test", 1)
    end

    test "invalidate is idempotent" do
      :ok = ParsedTemplate.put("test", 1, @sample_ast)

      :ok = ParsedTemplate.invalidate("test", 1)
      assert :miss = ParsedTemplate.get("test", 1)

      # Invalidate again
      :ok = ParsedTemplate.invalidate("test", 1)
      assert :miss = ParsedTemplate.get("test", 1)
    end

    test "invalidates specific version only" do
      ast1 = {:template, [children: [{:text, "V1"}]]}
      ast2 = {:template, [children: [{:text, "V2"}]]}

      :ok = ParsedTemplate.put("test", 1, ast1)
      :ok = ParsedTemplate.put("test", 2, ast2)

      # Invalidate only version 1
      :ok = ParsedTemplate.invalidate("test", 1)

      assert :miss = ParsedTemplate.get("test", 1)
      assert {:ok, ^ast2} = ParsedTemplate.get("test", 2)
    end
  end

  describe "when cache is disabled" do
    setup do
      Application.put_env(:sfera_doc, :cache, enabled: false)
      :ok
    end

    test "get/2 always returns :miss" do
      assert :miss = ParsedTemplate.get("test", 1)
    end

    test "put/3 is a no-op" do
      # Should not crash even though cache is disabled
      assert :ok = ParsedTemplate.put("test", 1, @sample_ast)

      # get should still return :miss
      assert :miss = ParsedTemplate.get("test", 1)
    end

    test "invalidate/2 is a no-op" do
      assert :ok = ParsedTemplate.invalidate("test", 1)
    end
  end

  describe "GenServer lifecycle" do
    test "starts successfully" do
      Application.put_env(:sfera_doc, :cache, enabled: true)

      assert {:ok, pid} = ParsedTemplate.start_link()
      assert Process.alive?(pid)
      assert GenServer.whereis(ParsedTemplate) == pid
    end

    test "creates ETS table on init" do
      Application.put_env(:sfera_doc, :cache, enabled: true)
      {:ok, _pid} = ParsedTemplate.start_link()

      # Verify ETS table exists
      assert :ets.info(:sfera_doc_ast_cache) != :undefined
    end

    test "stops gracefully" do
      Application.put_env(:sfera_doc, :cache, enabled: true)
      {:ok, pid} = ParsedTemplate.start_link()

      GenServer.stop(pid)

      refute Process.alive?(pid)
    end
  end

  describe "default configuration" do
    test "cache is enabled by default" do
      Application.delete_env(:sfera_doc, :cache)

      # Should be enabled by default
      assert SferaDoc.Config.cache_enabled?() == true
    end

    test "default TTL is 300 seconds" do
      Application.delete_env(:sfera_doc, :cache)

      assert SferaDoc.Config.cache_ttl() == 300
    end
  end
end
