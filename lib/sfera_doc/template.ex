defmodule SferaDoc.Template do
  @moduledoc """
  The domain struct representing a versioned Liquid template.

  This is the canonical type used throughout the library regardless of which
  storage backend is configured. Adapters convert their internal representation
  (Ecto schema record, ETS tuple, Redis JSON) into this struct.

  ## Fields

  - `:id`: internal identifier (UUID string for Ecto, integer for ETS, string for Redis)
  - `:name`: human-readable identifier used in the public API (e.g. `"invoice"`)
  - `:body`: Liquid template source string
  - `:version`: monotonically increasing integer per name; starts at 1
  - `:is_active`: `true` for the currently active version of a given name
  - `:variables_schema`: optional map declaring required/optional variables:
    `%{"required" => ["name", "date"], "optional" => ["footer"]}`
  - `:inserted_at` / `:updated_at`: timestamps

  ## Variable Validation

  Use `validate_variables/2` before rendering to ensure all required variables are present in the assigns map.
  """

  @enforce_keys [:name, :body]

  defstruct [
    :id,
    :name,
    :body,
    :version,
    :is_active,
    :variables_schema,
    :inserted_at,
    :updated_at
  ]

  @type t :: %__MODULE__{
          id: String.t() | integer() | nil,
          name: String.t(),
          body: String.t(),
          version: pos_integer() | nil,
          is_active: boolean() | nil,
          variables_schema: %{optional(String.t()) => [String.t()]} | nil,
          inserted_at: DateTime.t() | nil,
          updated_at: DateTime.t() | nil
        }

  @doc """
  Validates that all required variables from `variables_schema` are present in the `assigns` map.

  Returns `:ok` when:
  - no `variables_schema` is set, or
  - `variables_schema` has no `"required"` key, or
  - all required keys are present in `assigns`

  Returns `{:error, {:missing_variables, [String.t()]}}` listing missing keys.

  Returns `{:error, :assigns_must_be_map}` when `assigns` is not a map.

  ## Examples

      iex> t = %SferaDoc.Template{name: "t", body: "x", variables_schema: %{"required" => ["name"]}}
      iex> SferaDoc.Template.validate_variables(t, %{"name" => "Alice"})
      :ok

      iex> SferaDoc.Template.validate_variables(t, %{})
      {:error, {:missing_variables, ["name"]}}
  """
  @spec validate_variables(t(), term()) ::
          :ok
          | {:error, {:missing_variables, [String.t()]}}
          | {:error, :assigns_must_be_map}
  def validate_variables(%__MODULE__{}, assigns) when not is_map(assigns) do
    {:error, :assigns_must_be_map}
  end

  def validate_variables(%__MODULE__{variables_schema: nil}, _assigns), do: :ok

  def validate_variables(%__MODULE__{variables_schema: schema}, assigns) do
    required =
      case Map.get(schema, "required", []) do
        list when is_list(list) -> list
        _ -> []
      end

    missing = Enum.reject(required, &Map.has_key?(assigns, &1))

    case missing do
      [] -> :ok
      _ -> {:error, {:missing_variables, missing}}
    end
  end
end
