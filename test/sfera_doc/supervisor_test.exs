defmodule SferaDoc.SupervisorTest do
  use ExUnit.Case, async: false

  alias SferaDoc.Supervisor, as: SferaSupervisor

  setup do
    # Store original config
    original_store = Application.get_env(:sfera_doc, :store)
    original_pdf_engine = Application.get_env(:sfera_doc, :pdf_engine)
    original_chromic_pdf = Application.get_env(:sfera_doc, :chromic_pdf)
    original_cache = Application.get_env(:sfera_doc, :cache)
    original_pdf_hot_cache = Application.get_env(:sfera_doc, :pdf_hot_cache)
    original_pdf_object_store = Application.get_env(:sfera_doc, :pdf_object_store)

    on_exit(fn ->
      # Restore original config
      restore_env(:store, original_store)
      restore_env(:pdf_engine, original_pdf_engine)
      restore_env(:chromic_pdf, original_chromic_pdf)
      restore_env(:cache, original_cache)
      restore_env(:pdf_hot_cache, original_pdf_hot_cache)
      restore_env(:pdf_object_store, original_pdf_object_store)
    end)

    :ok
  end

  defp restore_env(key, nil), do: Application.delete_env(:sfera_doc, key)
  defp restore_env(key, value), do: Application.put_env(:sfera_doc, key, value)

  describe "init/1" do
    test "returns child specs with :one_for_one strategy" do
      # Configure minimal setup
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.put_env(:sfera_doc, :cache, enabled: true)

      {:ok, {strategy_opts, children}} = SferaSupervisor.init([])

      assert strategy_opts.strategy == :one_for_one
      assert strategy_opts.intensity == 3
      assert strategy_opts.period == 5
      assert is_list(children)
      assert length(children) > 0
    end

    test "filters out nil worker specs" do
      # Configure to disable optional components
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.put_env(:sfera_doc, :cache, enabled: false)
      Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: nil)
      Application.put_env(:sfera_doc, :pdf_object_store, adapter: nil)
      Application.put_env(:sfera_doc, :chromic_pdf, disabled: true)

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      # Should only have store worker (cache and others are disabled)
      assert is_list(children)

      # Verify no nil specs made it through
      refute nil in children
    end

    test "includes ParsedTemplate cache when enabled" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.put_env(:sfera_doc, :cache, enabled: true)

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      cache_spec = Enum.find(children, fn spec -> spec[:id] == SferaDoc.Cache.ParsedTemplate end)
      assert cache_spec != nil
    end

    test "excludes ParsedTemplate cache when disabled" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.put_env(:sfera_doc, :cache, enabled: false)

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      cache_spec = Enum.find(children, fn spec -> spec[:id] == SferaDoc.Cache.ParsedTemplate end)
      assert cache_spec == nil
    end

    test "includes store worker spec" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      store_spec = Enum.find(children, fn spec -> spec[:id] == SferaDoc.Store.ETS end)
      assert store_spec != nil
    end

    test "includes HotCache when configured with ETS" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :ets)

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      hot_cache_spec = Enum.find(children, fn spec -> spec[:id] == SferaDoc.Pdf.HotCache end)
      assert hot_cache_spec != nil
    end

    test "excludes HotCache when not configured" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.delete_env(:sfera_doc, :pdf_hot_cache)

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      hot_cache_spec = Enum.find(children, fn spec -> spec[:id] == SferaDoc.Pdf.HotCache end)
      assert hot_cache_spec == nil
    end
  end

  describe "store_worker_spec/0" do
    test "returns spec for ETS store" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      ets_spec = Enum.find(children, fn spec -> spec[:id] == SferaDoc.Store.ETS end)
      assert ets_spec != nil
      assert ets_spec[:start] == {SferaDoc.Store.ETS, :start_link, []}
    end

    test "returns nil for Ecto store (managed by host app)" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: SferaDoc.TestRepo
      )

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      # Ecto store should not be in children (it returns nil worker_spec)
      ecto_spec = Enum.find(children, fn spec -> Map.get(spec, :id) == SferaDoc.Store.Ecto end)
      assert ecto_spec == nil
    end

    test "raises error when store adapter module is missing" do
      # Configure non-existent adapter
      Application.put_env(:sfera_doc, :store, adapter: NonExistentAdapter)

      assert_raise RuntimeError, ~r/store adapter module is not available/, fn ->
        SferaSupervisor.init([])
      end
    end

    test "returns nil when no store configured" do
      Application.delete_env(:sfera_doc, :store)

      # Should not raise, just return no store worker
      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      assert is_list(children)
    end
  end

  describe "chromic_pdf_spec/0" do
    @tag :skip
    test "returns ChromicPDF spec when using ChromicPDF engine" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.put_env(:sfera_doc, :pdf_engine, adapter: SferaDoc.PdfEngine.ChromicPDF)
      Application.put_env(:sfera_doc, :chromic_pdf, session_pool: [size: 2])

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      chromic_spec =
        Enum.find(children, fn
          {ChromicPDF, _opts} -> true
          _ -> false
        end)

      assert chromic_spec != nil
      {mod, opts} = chromic_spec
      assert mod == ChromicPDF
      assert opts[:session_pool] == [size: 2]
      refute Keyword.has_key?(opts, :disabled)
    end

    test "excludes ChromicPDF when disabled flag is set" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.put_env(:sfera_doc, :pdf_engine, adapter: SferaDoc.PdfEngine.ChromicPDF)
      Application.put_env(:sfera_doc, :chromic_pdf, disabled: true)

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      chromic_spec =
        Enum.find(children, fn
          {ChromicPDF, _opts} -> true
          _ -> false
        end)

      assert chromic_spec == nil
    end

    test "excludes ChromicPDF when using different PDF engine" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.put_env(:sfera_doc, :pdf_engine, adapter: CustomPdfEngine)

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      chromic_spec =
        Enum.find(children, fn
          {ChromicPDF, _opts} -> true
          _ -> false
        end)

      assert chromic_spec == nil
    end

    @tag :skip
    test "removes disabled flag from ChromicPDF opts" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.put_env(:sfera_doc, :pdf_engine, adapter: SferaDoc.PdfEngine.ChromicPDF)
      Application.put_env(:sfera_doc, :chromic_pdf, disabled: false, session_pool: [size: 3])

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      chromic_spec =
        Enum.find(children, fn
          {ChromicPDF, _opts} -> true
          _ -> false
        end)

      assert chromic_spec != nil
      {_mod, opts} = chromic_spec
      refute Keyword.has_key?(opts, :disabled)
      assert opts[:session_pool] == [size: 3]
    end
  end

  describe "multiple configuration scenarios" do
    test "handles minimal configuration" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      assert length(children) >= 1
      refute nil in children
    end

    test "handles full configuration with all components enabled" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)
      Application.put_env(:sfera_doc, :cache, enabled: true)
      Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :ets)
      Application.put_env(:sfera_doc, :pdf_engine, adapter: SferaDoc.PdfEngine.ChromicPDF)
      Application.put_env(:sfera_doc, :chromic_pdf, [])

      {:ok, {_strategy, children}} = SferaSupervisor.init([])

      # Should have multiple children
      assert length(children) >= 2
      refute nil in children
    end
  end
end
