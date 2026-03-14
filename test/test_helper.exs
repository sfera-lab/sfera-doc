ExUnit.start()

# Configure TestRepo for Ecto-based tests
Application.put_env(:sfera_doc, SferaDoc.TestRepo,
  database: ":memory:",
  pool_size: 1
)

# Start TestRepo
{:ok, _} = SferaDoc.TestRepo.start_link()

# Create sfera_doc_templates table directly with SQL
# This avoids the need for schema_migrations table and Ecto.Migrator
Ecto.Adapters.SQL.query!(
  SferaDoc.TestRepo,
  """
  CREATE TABLE IF NOT EXISTS sfera_doc_templates (
    id BLOB PRIMARY KEY,
    name TEXT NOT NULL,
    body TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1,
    is_active INTEGER NOT NULL DEFAULT 0,
    variables_schema TEXT,
    inserted_at TEXT NOT NULL,
    updated_at TEXT NOT NULL
  )
  """
)

Ecto.Adapters.SQL.query!(
  SferaDoc.TestRepo,
  "CREATE INDEX IF NOT EXISTS sfera_doc_templates_name_index ON sfera_doc_templates (name)"
)

Ecto.Adapters.SQL.query!(
  SferaDoc.TestRepo,
  "CREATE UNIQUE INDEX IF NOT EXISTS sfera_doc_templates_name_version_index ON sfera_doc_templates (name, version)"
)
