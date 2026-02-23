if Code.ensure_loaded?(Ecto.Adapters.SQL) do
  defmodule SferaDoc.Store.Ecto.Record do
    @moduledoc false
    # Internal Ecto schema for the sfera_doc_templates table.
    # External code should work with SferaDoc.Template structs, not this module.
    use Ecto.Schema
    import Ecto.Changeset
    import Ecto.Query

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id

    # Table name is resolved at compile time so the schema macro can embed it.
    @table_name SferaDoc.Config.ecto_table_name()

    schema @table_name do
      field(:name, :string)
      field(:body, :string)
      field(:version, :integer, default: 1)
      field(:is_active, :boolean, default: false)
      field(:variables_schema, :map)

      timestamps(type: :utc_datetime)
    end

    @required_fields ~w(name body version is_active)a
    @optional_fields ~w(variables_schema)a

    def changeset(record, attrs) do
      record
      |> cast(attrs, @required_fields ++ @optional_fields)
      |> validate_required(@required_fields)
      |> validate_length(:name, min: 1, max: 255)
      |> unique_constraint([:name, :version])
    end

    # ---------------------------------------------------------------------------
    # Query helpers
    # ---------------------------------------------------------------------------

    def active_query(name) do
      from(r in __MODULE__,
        where: r.name == ^name and r.is_active == true,
        limit: 1
      )
    end

    def version_query(name, version) do
      from(r in __MODULE__,
        where: r.name == ^name and r.version == ^version,
        limit: 1
      )
    end

    def versions_query(name) do
      from(r in __MODULE__,
        where: r.name == ^name,
        order_by: [desc: r.version]
      )
    end

    def all_active_query do
      from(r in __MODULE__,
        where: r.is_active == true,
        order_by: [asc: r.name]
      )
    end

    def deactivate_query(name) do
      from(r in __MODULE__,
        where: r.name == ^name and r.is_active == true
      )
    end

    @doc "Returns the next version number for the given template name."
    def next_version(repo, name) do
      max =
        from(r in __MODULE__, where: r.name == ^name, select: max(r.version))
        |> repo.one()

      (max || 0) + 1
    end

    # ---------------------------------------------------------------------------
    # Conversion
    # ---------------------------------------------------------------------------

    @doc "Converts an Ecto record to a `SferaDoc.Template` struct."
    def to_template(%__MODULE__{} = r) do
      %SferaDoc.Template{
        id: r.id,
        name: r.name,
        body: r.body,
        version: r.version,
        is_active: r.is_active,
        variables_schema: r.variables_schema,
        inserted_at: r.inserted_at,
        updated_at: r.updated_at
      }
    end
  end
end
