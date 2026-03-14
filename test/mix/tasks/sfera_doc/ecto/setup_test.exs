defmodule Mix.Tasks.SferaDoc.Ecto.SetupTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.SferaDoc.Ecto.Setup

  @temp_dir "tmp/test_migrations"

  setup do
    # Store original config
    original_store = Application.get_env(:sfera_doc, :store)

    # Clean up and recreate temp directory
    File.rm_rf!(@temp_dir)
    File.mkdir_p!(@temp_dir)

    on_exit(fn ->
      # Cleanup temp files
      File.rm_rf!(@temp_dir)

      # Restore config
      if original_store do
        Application.put_env(:sfera_doc, :store, original_store)
      else
        Application.delete_env(:sfera_doc, :store)
      end
    end)

    :ok
  end

  describe "run/1" do
    test "creates migration file with correct timestamp format" do
      # Configure a test repo
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: SferaDoc.TestRepo
      )

      # Run task and capture output
      output =
        capture_io(fn ->
          # Change to temp directory for this test
          File.cd!(@temp_dir, fn ->
            Setup.run([])
          end)
        end)

      # Check that migration was created
      assert output =~ "Creating priv/test_repo/migrations/"
      assert output =~ "_create_sfera_doc_templates.exs"
      assert output =~ "Run `mix ecto.migrate` to apply the migration"

      # Verify file exists
      migrations_dir = Path.join([@temp_dir, "priv", "test_repo", "migrations"])
      assert File.exists?(migrations_dir)

      [migration_file] = File.ls!(migrations_dir)
      assert migration_file =~ ~r/^\d{14}_create_sfera_doc_templates\.exs$/
    end

    test "generates correct migration content" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: SferaDoc.TestRepo
      )

      capture_io(fn ->
        File.cd!(@temp_dir, fn ->
          Setup.run([])
        end)
      end)

      # Read generated file
      migrations_dir = Path.join([@temp_dir, "priv", "test_repo", "migrations"])
      [migration_file] = File.ls!(migrations_dir)
      filepath = Path.join(migrations_dir, migration_file)
      content = File.read!(filepath)

      # Verify content
      assert content =~ "defmodule SferaDoc.TestRepo.Migrations.CreateSferaDocTemplates do"
      assert content =~ "use SferaDoc.Store.Ecto.Migration"
      assert content =~ "end"
    end

    test "creates migrations directory if it doesn't exist" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: SferaDoc.TestRepo
      )

      migrations_dir = Path.join([@temp_dir, "priv", "test_repo", "migrations"])
      refute File.exists?(migrations_dir)

      capture_io(fn ->
        File.cd!(@temp_dir, fn ->
          Setup.run([])
        end)
      end)

      assert File.exists?(migrations_dir)
    end

    test "uses repo name to determine migration path" do
      # Configure with a differently named repo
      defmodule MyApp.CustomRepo do
        def __adapter__, do: Ecto.Adapters.Postgres
      end

      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: MyApp.CustomRepo
      )

      output =
        capture_io(fn ->
          File.cd!(@temp_dir, fn ->
            Setup.run([])
          end)
        end)

      # Should use custom_repo in path
      assert output =~ "priv/custom_repo/migrations/"
    end

    test "generates unique timestamps for multiple runs" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: SferaDoc.TestRepo
      )

      # Run twice
      capture_io(fn ->
        File.cd!(@temp_dir, fn ->
          Setup.run([])
          # Ensure different timestamp (second precision)
          Process.sleep(1100)
          Setup.run([])
        end)
      end)

      migrations_dir = Path.join([@temp_dir, "priv", "test_repo", "migrations"])
      files = File.ls!(migrations_dir)

      # Should have two different files
      assert length(files) == 2
      [file1, file2] = Enum.sort(files)
      refute file1 == file2
    end

    test "raises error when no repo is configured" do
      Application.delete_env(:sfera_doc, :store)

      assert_raise Mix.Error, ~r/no Ecto repo configured/, fn ->
        capture_io(fn ->
          File.cd!(@temp_dir, fn ->
            Setup.run([])
          end)
        end)
      end
    end

    test "raises error when repo config is invalid" do
      Application.put_env(:sfera_doc, :store, adapter: SferaDoc.Store.ETS)

      assert_raise Mix.Error, ~r/no Ecto repo configured/, fn ->
        capture_io(fn ->
          File.cd!(@temp_dir, fn ->
            Setup.run([])
          end)
        end)
      end
    end
  end

  describe "timestamp format" do
    test "generates valid timestamp in YYYYMMDDHHMMss format" do
      Application.put_env(:sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: SferaDoc.TestRepo
      )

      capture_io(fn ->
        File.cd!(@temp_dir, fn ->
          Setup.run([])
        end)
      end)

      migrations_dir = Path.join([@temp_dir, "priv", "test_repo", "migrations"])
      [migration_file] = File.ls!(migrations_dir)

      # Extract timestamp from filename
      timestamp = String.slice(migration_file, 0, 14)

      # Verify it's 14 digits
      assert String.length(timestamp) == 14
      assert String.match?(timestamp, ~r/^\d{14}$/)

      # Verify it parses to a valid datetime
      year = String.to_integer(String.slice(timestamp, 0, 4))
      month = String.to_integer(String.slice(timestamp, 4, 2))
      day = String.to_integer(String.slice(timestamp, 6, 2))
      hour = String.to_integer(String.slice(timestamp, 8, 2))
      minute = String.to_integer(String.slice(timestamp, 10, 2))
      second = String.to_integer(String.slice(timestamp, 12, 2))

      assert year >= 2024
      assert month >= 1 and month <= 12
      assert day >= 1 and day <= 31
      assert hour >= 0 and hour <= 23
      assert minute >= 0 and minute <= 59
      assert second >= 0 and second <= 59
    end
  end
end
