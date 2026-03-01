defmodule SferaDoc.TestRepo.Migrations.CreateSferaDocTemplates do
  use Ecto.Migration

  def up do
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
  end

  def down do
    drop table(:sfera_doc_templates)
  end
end
