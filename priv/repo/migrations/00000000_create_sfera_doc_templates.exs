defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
  use Ecto.Migration

  # This is the expanded reference migration. For most setups you can use the
  # shorter form instead:
  #
  #     defmodule MyApp.Repo.Migrations.CreateSferaDocTemplates do
  #       use SferaDoc.Store.Ecto.Migration
  #     end
  #
  # Use this expanded form only when you need to customise columns, indexes,
  # or skip PostgreSQL-specific DDL (see comments below).
  #
  # This migration assumes the default table name of "sfera_doc_templates"
  # is being used. If you have overridden that via configuration, you should
  # change this migration accordingly.

  def up do
    # Required for UUID generation on PostgreSQL — omit for SQLite or MySQL
    execute("CREATE EXTENSION IF NOT EXISTS pgcrypto", "")

    create table(:sfera_doc_templates, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string, null: false, size: 255
      add :body, :text, null: false
      add :version, :integer, null: false, default: 1
      add :is_active, :boolean, null: false, default: false
      add :variables_schema, :map

      timestamps(type: :utc_datetime)
    end

    create index(:sfera_doc_templates, [:name])
    create unique_index(:sfera_doc_templates, [:name, :version])

    # PostgreSQL partial unique index to enforce only one active version per template name.
    # Remove this if you are not using PostgreSQL.
    execute("""
    CREATE UNIQUE INDEX sfera_doc_templates_name_active_idx
    ON sfera_doc_templates (name)
    WHERE is_active = true
    """)
  end

  def down do
    # Drops the table and all associated indexes (including the partial unique
    # index). The pgcrypto extension is intentionally NOT dropped here as other
    # tables in the database may depend on it.
    drop table(:sfera_doc_templates)
  end
end
