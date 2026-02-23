defmodule SferaDoc.Pdf.ObjectStore.Adapter do
  @moduledoc """
  Behaviour that all SferaDoc PDF object-storage adapters must implement.

  Object storage is the **durable source of truth** for rendered PDFs. Adapters
  persist PDF binaries keyed by `{name, version, assigns_hash}` so that identical
  renders survive BEAM restarts without re-invoking Chrome.

  ## Implementing a Custom Adapter

  1. `@behaviour SferaDoc.Pdf.ObjectStore.Adapter`
  2. Implement all callbacks
  3. Return `nil` from `worker_spec/0` if your adapter manages its own connections
     externally (e.g. HTTP-based S3/Azure clients)
  4. Configure the library to use your adapter:

         config :sfera_doc, :pdf_object_store,
           adapter: MyApp.CustomAdapter,
           my_option: "value"
  """

  @type name :: String.t()
  @type version :: pos_integer()
  @type assigns_hash :: String.t()
  @type reason :: any()

  @doc """
  Returns a child spec for processes this adapter needs, or `nil` if the adapter
  manages its own connections (e.g. HTTP-based clients).
  """
  @callback worker_spec() :: Supervisor.child_spec() | nil

  @doc """
  Retrieves a stored PDF binary. Returns `{:ok, binary}` on hit, `:miss` if the
  object does not exist, or `{:error, reason}` on storage failure (treated as `:miss`).
  """
  @callback get(name(), version(), assigns_hash()) ::
              {:ok, binary()} | :miss | {:error, reason()}

  @doc """
  Persists a rendered PDF binary. Returns `:ok` on success or `{:error, reason}` on
  failure. Failures are logged but do not abort the render pipeline.
  """
  @callback put(name(), version(), assigns_hash(), binary()) ::
              :ok | {:error, reason()}
end
