cond do
  Code.ensure_loaded?(Ecto) ->
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
      @behaviour SferaDoc.Store.Adapter

      alias SferaDoc.Store.Ecto.Record
      alias SferaDoc.{Config, Template}
      import Ecto.Query

      # Returns the configured Ecto repo at runtime, supporting hot reloads.
      # Raises RuntimeError if `:repo` is not configured (surfaces at call time,
      # not at startup — see Config.ecto_repo/0 for details).
      defp repo, do: Config.ecto_repo()

      @impl SferaDoc.Store.Adapter
      def worker_spec, do: nil

      @impl SferaDoc.Store.Adapter
      def get(name) do
        case repo().one(Record.active_query(name)) do
          nil -> {:error, :not_found}
          record -> {:ok, Record.to_template(record)}
        end
      rescue
        e -> {:error, e}
      end

      @impl SferaDoc.Store.Adapter
      def get_version(name, version) do
        case repo().one(Record.version_query(name, version)) do
          nil -> {:error, :not_found}
          record -> {:ok, Record.to_template(record)}
        end
      rescue
        e -> {:error, e}
      end

      @impl SferaDoc.Store.Adapter
      def put(%Template{} = template) do
        # NOTE: `next_version` is computed via SELECT MAX(version) inside the
        # Multi, without a row lock. Under concurrent `put` calls for the same
        # name, two transactions may compute the same version and then conflict
        # on the unique_constraint([:name, :version]). This surfaces as
        # `{:error, {:validation, %Ecto.Changeset{}}}` with a uniqueness error.
        # Callers that need strict ordering under high concurrency should
        # implement their own retry logic or use a database-level sequence.
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
        |> repo().transaction()
        |> case do
          {:ok, %{insert: record}} -> {:ok, Record.to_template(record)}
          {:error, _op, %Ecto.Changeset{} = cs, _changes} -> {:error, {:validation, cs}}
          {:error, _op, reason, _changes} -> {:error, reason}
        end
      rescue
        e -> {:error, e}
      end

      @impl SferaDoc.Store.Adapter
      def list do
        {:ok, repo().all(Record.all_active_query()) |> Enum.map(&Record.to_template/1)}
      rescue
        e -> {:error, e}
      end

      @impl SferaDoc.Store.Adapter
      def list_versions(name) do
        {:ok, repo().all(Record.versions_query(name)) |> Enum.map(&Record.to_template/1)}
      rescue
        e -> {:error, e}
      end

      @impl SferaDoc.Store.Adapter
      def activate_version(name, version) do
        Ecto.Multi.new()
        |> Ecto.Multi.one(:target, Record.version_query(name, version))
        |> Ecto.Multi.run(:check_exists, fn _repo, %{target: target} ->
          cond do
            target -> {:ok, target}
            true -> {:error, :not_found}
          end
        end)
        |> Ecto.Multi.update_all(
          :deactivate,
          Record.deactivate_query(name),
          set: [is_active: false]
        )
        # NOTE: `target` was fetched before `:deactivate` ran. If `target` was
        # the currently active record, its `is_active` field is stale (true in
        # the struct, false in the DB after deactivate). The changeset below
        # explicitly sets `is_active: true`, which is the intended final state,
        # so correctness is maintained regardless of the stale field.
        |> Ecto.Multi.update(:activate, fn %{target: target} ->
          Record.changeset(target, %{is_active: true})
        end)
        |> repo().transaction()
        |> case do
          {:ok, %{activate: record}} -> {:ok, Record.to_template(record)}
          {:error, :check_exists, :not_found, _} -> {:error, :not_found}
          {:error, _op, reason, _changes} -> {:error, reason}
        end
      rescue
        e -> {:error, e}
      end

      @impl SferaDoc.Store.Adapter
      # Delete is idempotent: returns :ok even if no rows were deleted.
      # This matches the Adapter callback contract (:ok | {:error, reason()}).
      def delete(name) do
        from(r in Record, where: r.name == ^name)
        |> repo().delete_all()

        :ok
      rescue
        e -> {:error, e}
      end
    end

  true ->
    nil
end
