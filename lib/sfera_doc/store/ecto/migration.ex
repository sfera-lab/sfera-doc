defmodule SferaDoc.Store.Ecto.Migration do
  @moduledoc """
  Migration helper for creating the `sfera_doc_templates` table.

  ## Usage

  Generate a migration in your app and `use` this module:

      defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
        use SferaDoc.Store.Ecto.Migration
      end

  Then run `mix ecto.migrate`.

  ## Partial Unique Index (PostgreSQL)

  On PostgreSQL, a partial unique index on `(name) WHERE is_active = true`
  enforces the "one active version per template name" invariant at the
  database level without advisory locks.

  On MySQL and SQLite this index is omitted (partial indexes are not supported
  or behave differently) — the application layer handles the invariant instead.
  """

  defmacro __using__(_opts) do
    quote do
      use Ecto.Migration

      def up do
        table_name = SferaDoc.Config.ecto_table_name()

        create table(table_name, primary_key: false) do
          add(:id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()"))
          add(:name, :string, null: false, size: 255)
          add(:body, :text, null: false)
          add(:version, :integer, null: false, default: 1)
          add(:is_active, :boolean, null: false, default: false)
          add(:variables_schema, :map)

          timestamps(type: :utc_datetime)
        end

        create(index(table_name, [:name]))
        create(unique_index(table_name, [:name, :version]))

        # Partial unique index: at most one active version per template name.
        # Only created on PostgreSQL; MySQL/SQLite do not support this syntax.
        if repo().__adapter__() == Ecto.Adapters.Postgres do
          execute(
            """
            CREATE UNIQUE INDEX #{table_name}_name_active_idx
              ON #{table_name} (name)
              WHERE is_active = true
            """,
            "DROP INDEX IF EXISTS #{table_name}_name_active_idx"
          )
        end
      end

      def down do
        table_name = SferaDoc.Config.ecto_table_name()
        drop(table(table_name))
      end
    end
  end
end
