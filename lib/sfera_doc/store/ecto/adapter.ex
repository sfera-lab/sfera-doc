defmodule SferaDoc.Store.Ecto do
  @moduledoc """
  Ecto-backed storage adapter for SferaDoc.

  Works with PostgreSQL, MySQL, and SQLite via `ecto_sql`.

  ## Configuration

      config :sfera_doc, :store,
        adapter: SferaDoc.Store.Ecto,
        repo: MyApp.Repo

  The Ecto repo is managed by the host application's supervision tree.
  SferaDoc does not start or supervise it (`worker_spec/0` returns `nil`).

  ## Database Setup

  Add a migration to your app:

      defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
        use SferaDoc.Store.Ecto.Migration
      end

  Or run: `mix sfera_doc.ecto.setup`
  """
  if Code.ensure_loaded?(Ecto.Query) do
    @behaviour SferaDoc.Store.Adapter

    alias SferaDoc.Store.Ecto.Record
    alias SferaDoc.{Config, Template}
    import Ecto.Query

    # ---------------------------------------------------------------------------
    # worker_spec/0
    # ---------------------------------------------------------------------------

    @impl SferaDoc.Store.Adapter
    def worker_spec, do: nil

    # ---------------------------------------------------------------------------
    # get/1
    # ---------------------------------------------------------------------------

    @impl SferaDoc.Store.Adapter
    def get(name) do
      repo = Config.ecto_repo()

      case repo.one(Record.active_query(name)) do
        nil -> {:error, :not_found}
        record -> {:ok, Record.to_template(record)}
      end
    rescue
      e -> {:error, e}
    end

    # ---------------------------------------------------------------------------
    # get_version/2
    # ---------------------------------------------------------------------------

    @impl SferaDoc.Store.Adapter
    def get_version(name, version) do
      repo = Config.ecto_repo()

      case repo.one(Record.version_query(name, version)) do
        nil -> {:error, :not_found}
        record -> {:ok, Record.to_template(record)}
      end
    rescue
      e -> {:error, e}
    end

    # ---------------------------------------------------------------------------
    # put/1
    # ---------------------------------------------------------------------------

    @impl SferaDoc.Store.Adapter
    def put(%Template{} = template) do
      repo = Config.ecto_repo()

      Ecto.Multi.new()
      |> Ecto.Multi.run(:next_version, fn repo, _changes ->
        {:ok, Record.next_version(repo, template.name)}
      end)
      |> Ecto.Multi.update_all(
        :deactivate,
        Record.deactivate_query(template.name),
        set: [is_active: false]
      )
      |> Ecto.Multi.insert(:insert, fn %{next_version: v} ->
        Record.changeset(%Record{}, %{
          name: template.name,
          body: template.body,
          version: v,
          is_active: true,
          variables_schema: template.variables_schema
        })
      end)
      |> repo.transaction()
      |> case do
        {:ok, %{insert: record}} -> {:ok, Record.to_template(record)}
        {:error, _op, reason, _changes} -> {:error, reason}
      end
    rescue
      e -> {:error, e}
    end

    # ---------------------------------------------------------------------------
    # list/0
    # ---------------------------------------------------------------------------

    @impl SferaDoc.Store.Adapter
    def list do
      repo = Config.ecto_repo()
      {:ok, repo.all(Record.all_active_query()) |> Enum.map(&Record.to_template/1)}
    rescue
      e -> {:error, e}
    end

    # ---------------------------------------------------------------------------
    # list_versions/1
    # ---------------------------------------------------------------------------

    @impl SferaDoc.Store.Adapter
    def list_versions(name) do
      repo = Config.ecto_repo()
      {:ok, repo.all(Record.versions_query(name)) |> Enum.map(&Record.to_template/1)}
    rescue
      e -> {:error, e}
    end

    # ---------------------------------------------------------------------------
    # activate_version/2
    # ---------------------------------------------------------------------------

    @impl SferaDoc.Store.Adapter
    def activate_version(name, version) do
      repo = Config.ecto_repo()

      Ecto.Multi.new()
      |> Ecto.Multi.one(:target, Record.version_query(name, version))
      |> Ecto.Multi.run(:check_exists, fn _repo, %{target: target} ->
        if target, do: {:ok, target}, else: {:error, :not_found}
      end)
      |> Ecto.Multi.update_all(
        :deactivate,
        Record.deactivate_query(name),
        set: [is_active: false]
      )
      |> Ecto.Multi.update(:activate, fn %{target: target} ->
        Record.changeset(target, %{is_active: true})
      end)
      |> repo.transaction()
      |> case do
        {:ok, %{activate: record}} -> {:ok, Record.to_template(record)}
        {:error, :check_exists, :not_found, _} -> {:error, :not_found}
        {:error, _op, reason, _changes} -> {:error, reason}
      end
    rescue
      e -> {:error, e}
    end

    # ---------------------------------------------------------------------------
    # delete/1
    # ---------------------------------------------------------------------------

    @impl SferaDoc.Store.Adapter
    def delete(name) do
      repo = Config.ecto_repo()

      from(r in Record, where: r.name == ^name)
      |> repo.delete_all()

      :ok
    rescue
      e -> {:error, e}
    end
  end
end
