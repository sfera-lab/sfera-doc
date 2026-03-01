cond do
  Code.ensure_loaded?(Ecto.Migration) ->
    defmodule SferaDoc.Store.Ecto.Migration do
      @moduledoc """
      Convenience module for creating the `sfera_doc_templates` migration.

      In the host application, create a migration file:

          defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
            use SferaDoc.Store.Ecto.Migration
          end

      Or run `mix sfera_doc.ecto.setup` to generate it automatically.

      ## Options

        * `:adapter` - the database adapter type. Defaults to `:postgres`.
          Set to `:sqlite` or `:mysql` to skip PostgreSQL-specific DDL
          (the `pgcrypto` extension and the partial unique index on `is_active`).

      ## Example (SQLite / MySQL)

          defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
            use SferaDoc.Store.Ecto.Migration, adapter: :sqlite
          end

      For full control (e.g. custom columns or indexes), copy the expanded
      migration from `priv/migrations/create_sfera_doc_templates.exs` and
      modify it as needed.
      """

      defmacro __using__(opts \\ []) do
        table_name = SferaDoc.Config.ecto_table_name()
        adapter = Keyword.get(opts, :adapter, :postgres)
        postgres? = adapter == :postgres

        partial_index_sql = """
        CREATE UNIQUE INDEX #{table_name}_name_active_idx
        ON #{table_name} (name)
        WHERE is_active = true
        """

        quote do
          use Ecto.Migration

          def up do
            # pgcrypto is required for UUID generation on PostgreSQL.
            # It is a no-op if the extension is already installed.
            # Omitted for SQLite and MySQL.
            if unquote(postgres?) do
              execute("CREATE EXTENSION IF NOT EXISTS pgcrypto", "")
            end

            create table(unquote(table_name), primary_key: false) do
              add :id, :binary_id, primary_key: true
              add :name, :string, null: false, size: 255
              add :body, :text, null: false
              add :version, :integer, null: false, default: 1
              add :is_active, :boolean, null: false, default: false
              add :variables_schema, :map

              timestamps(type: :utc_datetime)
            end

            create index(unquote(table_name), [:name])
            create unique_index(unquote(table_name), [:name, :version])

            # Partial unique index: only one active version per template name.
            # PostgreSQL-specific; omitted for SQLite and MySQL.
            if unquote(postgres?) do
              execute(unquote(partial_index_sql), "")
            end
          end

          def down do
            # Drops the table and all associated indexes (including the partial
            # unique index created in up/0). The pgcrypto extension is
            # intentionally NOT dropped here as other tables may depend on it.
            drop table(unquote(table_name))
          end
        end
      end
    end

  true ->
    nil
end
