defmodule SferaDoc.Store.Adapter do
  @moduledoc """
  Behaviour that all SferaDoc storage backends must implement.

  Templates are identified by their `name` (a human-readable string). Each name
  can have multiple numbered versions; at most one version per name is active at
  any time.

  ## Implementing a Custom Adapter

  1. `use` or `@behaviour SferaDoc.Store.Adapter`
  2. Implement all callbacks
  3. Return `nil` from `worker_spec/0` if your adapter uses an externally
     supervised process (e.g. an Ecto Repo managed by the host application)
  4. Configure the library to use your adapter:

         config :sfera_doc, :store, adapter: MyApp.CustomAdapter
  """

  alias SferaDoc.Template

  @type name :: String.t()
  @type version :: pos_integer()
  @type reason :: any()

  @doc """
  Returns a child spec for processes this adapter needs, or `nil` if the
  adapter relies on externally managed processes (e.g. Ecto repos).

  The supervisor filters out `nil` values, so returning `nil` is safe.
  """
  @callback worker_spec() :: Supervisor.child_spec() | nil

  @doc """
  Fetches the currently active template for the given name.
  """
  @callback get(name()) ::
              {:ok, Template.t()} | {:error, :not_found} | {:error, reason()}

  @doc """
  Fetches a specific version of a template by name and version number.
  """
  @callback get_version(name(), version()) ::
              {:ok, Template.t()} | {:error, :not_found} | {:error, reason()}

  @doc """
  Persists a new version of the template.

  The adapter is responsible for:
  - computing the next version number (`MAX(existing versions) + 1`, or `1` if new)
  - setting `is_active: true` on the new record
  - setting `is_active: false` on all previous versions for the same name

  Both create and update go through this single callback.
  """
  @callback put(Template.t()) :: {:ok, Template.t()} | {:error, reason()}

  @doc """
  Returns all templates (latest active version per name).
  """
  @callback list() :: {:ok, [Template.t()]} | {:error, reason()}

  @doc """
  Returns all versions for a given template name, ordered by version descending.
  """
  @callback list_versions(name()) :: {:ok, [Template.t()]} | {:error, reason()}

  @doc """
  Makes the given version the active one for the template name.
  Deactivates all other versions for that name.
  """
  @callback activate_version(name(), version()) ::
              {:ok, Template.t()} | {:error, :not_found} | {:error, reason()}

  @doc """
  Deletes all versions of a template by name.
  """
  @callback delete(name()) :: :ok | {:error, reason()}
end
