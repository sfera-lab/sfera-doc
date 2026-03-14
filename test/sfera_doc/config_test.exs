defmodule SferaDoc.ConfigTest do
  use ExUnit.Case, async: false

  alias SferaDoc.Config

  describe "ecto_table_name/0" do
    test "returns the configured table name" do
      # This is compile-time config, so it returns the default or configured value
      assert is_binary(Config.ecto_table_name())
    end
  end

  describe "store_adapter/0" do
    setup do
      original = Application.get_env(:sfera_doc, :store)

      on_exit(fn ->
        if original do
          Application.put_env(:sfera_doc, :store, original)
        else
          Application.delete_env(:sfera_doc, :store)
        end
      end)

      :ok
    end

    test "returns the configured adapter" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.TestStore)
      assert Config.store_adapter() == SferaDoc.TestStore
    end

    test "raises when no adapter is configured" do
      Application.delete_env(:sfera_doc, :store)

      assert_raise RuntimeError, ~r/no store adapter configured/, fn ->
        Config.store_adapter()
      end
    end

    test "raises when adapter is nil" do
      Application.put_env(:sfera_doc, :store, adapter: nil)

      assert_raise RuntimeError, ~r/no store adapter configured/, fn ->
        Config.store_adapter()
      end
    end
  end

  describe "ecto_repo/0" do
    setup do
      original = Application.get_env(:sfera_doc, :store)

      on_exit(fn ->
        if original do
          Application.put_env(:sfera_doc, :store, original)
        else
          Application.delete_env(:sfera_doc, :store)
        end
      end)

      :ok
    end

    test "returns the configured repo" do
      Application.put_env(:sfera_doc, :store, repo: MyApp.Repo)
      assert Config.ecto_repo() == MyApp.Repo
    end

    test "raises when no repo is configured" do
      Application.delete_env(:sfera_doc, :store)

      assert_raise RuntimeError, ~r/no Ecto repo configured/, fn ->
        Config.ecto_repo()
      end
    end

    test "raises when repo is nil" do
      Application.put_env(:sfera_doc, :store, repo: nil)

      assert_raise RuntimeError, ~r/no Ecto repo configured/, fn ->
        Config.ecto_repo()
      end
    end
  end

  describe "redis_config/0" do
    setup do
      original = Application.get_env(:sfera_doc, :redis)

      on_exit(fn ->
        if original do
          Application.put_env(:sfera_doc, :redis, original)
        else
          Application.delete_env(:sfera_doc, :redis)
        end
      end)

      :ok
    end

    test "returns configured redis options" do
      Application.put_env(:sfera_doc, :redis, host: "redis.example.com", port: 6380)
      config = Config.redis_config()
      assert config[:host] == "redis.example.com"
      assert config[:port] == 6380
    end

    test "returns default when not configured" do
      Application.delete_env(:sfera_doc, :redis)
      config = Config.redis_config()
      assert config[:host] == "localhost"
      assert config[:port] == 6379
    end
  end

  describe "cache_enabled?/0" do
    setup do
      original = Application.get_env(:sfera_doc, :cache)

      on_exit(fn ->
        if original do
          Application.put_env(:sfera_doc, :cache, original)
        else
          Application.delete_env(:sfera_doc, :cache)
        end
      end)

      :ok
    end

    test "returns true by default" do
      Application.delete_env(:sfera_doc, :cache)
      assert Config.cache_enabled?() == true
    end

    test "returns configured value" do
      Application.put_env(:sfera_doc, :cache, enabled: false)
      assert Config.cache_enabled?() == false

      Application.put_env(:sfera_doc, :cache, enabled: true)
      assert Config.cache_enabled?() == true
    end
  end

  describe "cache_ttl/0" do
    setup do
      original = Application.get_env(:sfera_doc, :cache)

      on_exit(fn ->
        if original do
          Application.put_env(:sfera_doc, :cache, original)
        else
          Application.delete_env(:sfera_doc, :cache)
        end
      end)

      :ok
    end

    test "returns 300 by default" do
      Application.delete_env(:sfera_doc, :cache)
      assert Config.cache_ttl() == 300
    end

    test "returns configured value" do
      Application.put_env(:sfera_doc, :cache, ttl: 600)
      assert Config.cache_ttl() == 600
    end
  end

  describe "pdf_hot_cache_adapter/0" do
    setup do
      original = Application.get_env(:sfera_doc, :pdf_hot_cache)

      on_exit(fn ->
        if original do
          Application.put_env(:sfera_doc, :pdf_hot_cache, original)
        else
          Application.delete_env(:sfera_doc, :pdf_hot_cache)
        end
      end)

      :ok
    end

    test "returns nil when not configured" do
      Application.delete_env(:sfera_doc, :pdf_hot_cache)
      assert Config.pdf_hot_cache_adapter() == nil
    end

    test "returns configured adapter" do
      Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :redis)
      assert Config.pdf_hot_cache_adapter() == :redis

      Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :ets)
      assert Config.pdf_hot_cache_adapter() == :ets
    end
  end

  describe "pdf_hot_cache_ttl/0" do
    setup do
      original = Application.get_env(:sfera_doc, :pdf_hot_cache)

      on_exit(fn ->
        if original do
          Application.put_env(:sfera_doc, :pdf_hot_cache, original)
        else
          Application.delete_env(:sfera_doc, :pdf_hot_cache)
        end
      end)

      :ok
    end

    test "returns 60 by default" do
      Application.delete_env(:sfera_doc, :pdf_hot_cache)
      assert Config.pdf_hot_cache_ttl() == 60
    end

    test "returns configured value" do
      Application.put_env(:sfera_doc, :pdf_hot_cache, ttl: 120)
      assert Config.pdf_hot_cache_ttl() == 120
    end
  end

  describe "pdf_object_store_adapter/0" do
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

    test "returns nil when not configured" do
      Application.delete_env(:sfera_doc, :pdf_object_store)
      assert Config.pdf_object_store_adapter() == nil
    end

    test "returns configured adapter" do
      Application.put_env(:sfera_doc, :pdf_object_store, adapter: SferaDoc.Pdf.ObjectStore.S3)

      assert Config.pdf_object_store_adapter() == SferaDoc.Pdf.ObjectStore.S3
    end
  end

  describe "pdf_object_store_opts/0" do
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

    test "returns empty list when not configured" do
      Application.delete_env(:sfera_doc, :pdf_object_store)
      assert Config.pdf_object_store_opts() == []
    end

    test "returns full configuration" do
      opts = [adapter: SferaDoc.Pdf.ObjectStore.S3, bucket: "my-bucket"]
      Application.put_env(:sfera_doc, :pdf_object_store, opts)
      assert Config.pdf_object_store_opts() == opts
    end
  end

  describe "chromic_pdf_opts/0" do
    setup do
      original = Application.get_env(:sfera_doc, :chromic_pdf)

      on_exit(fn ->
        if original do
          Application.put_env(:sfera_doc, :chromic_pdf, original)
        else
          Application.delete_env(:sfera_doc, :chromic_pdf)
        end
      end)

      :ok
    end

    test "returns empty list when not configured" do
      Application.delete_env(:sfera_doc, :chromic_pdf)
      assert Config.chromic_pdf_opts() == []
    end

    test "returns configured options" do
      opts = [pool_size: 2, timeout: 5000]
      Application.put_env(:sfera_doc, :chromic_pdf, opts)
      assert Config.chromic_pdf_opts() == opts
    end
  end

  describe "template_engine_adapter/0" do
    setup do
      original = Application.get_env(:sfera_doc, :template_engine)

      on_exit(fn ->
        if original do
          Application.put_env(:sfera_doc, :template_engine, original)
        else
          Application.delete_env(:sfera_doc, :template_engine)
        end
      end)

      :ok
    end

    test "returns default Solid adapter" do
      Application.delete_env(:sfera_doc, :template_engine)
      assert Config.template_engine_adapter() == SferaDoc.TemplateEngine.Solid
    end

    test "returns configured adapter" do
      Application.put_env(:sfera_doc, :template_engine, adapter: MyCustomEngine)
      assert Config.template_engine_adapter() == MyCustomEngine
    end
  end

  describe "pdf_engine_adapter/0" do
    setup do
      original = Application.get_env(:sfera_doc, :pdf_engine)

      on_exit(fn ->
        if original do
          Application.put_env(:sfera_doc, :pdf_engine, original)
        else
          Application.delete_env(:sfera_doc, :pdf_engine)
        end
      end)

      :ok
    end

    test "returns default ChromicPDF adapter" do
      Application.delete_env(:sfera_doc, :pdf_engine)
      assert Config.pdf_engine_adapter() == SferaDoc.PdfEngine.ChromicPDF
    end

    test "returns configured adapter" do
      Application.put_env(:sfera_doc, :pdf_engine, adapter: MyCustomPdfEngine)
      assert Config.pdf_engine_adapter() == MyCustomPdfEngine
    end
  end
end
