defmodule SferaDoc.Pdf.ObjectStore do
  @moduledoc """
  Facade for the PDF object storage tier.

  Object storage is the **durable source of truth** for rendered PDFs. When a PDF
  is found here it is returned directly (and populated into the hot cache), avoiding
  a Chrome render entirely. PDFs survive BEAM restarts.

  Configure an adapter to enable this tier:

      config :sfera_doc, :pdf_object_store,
        adapter: SferaDoc.Pdf.ObjectStore.S3,
        bucket: "my-pdfs"

  If no adapter is configured, all operations are no-ops and `get/3` always returns
  `:miss` so the pipeline falls through to generation.

  ## Available adapters

  | Module | Storage |
  |---|---|
  | `SferaDoc.Pdf.ObjectStore.S3` | Amazon S3 or S3-compatible |
  | `SferaDoc.Pdf.ObjectStore.Azure` | Azure Blob Storage |
  | `SferaDoc.Pdf.ObjectStore.FileSystem` | Local / shared file system |
  """

  require Logger

  @doc """
  Returns a child spec for the configured adapter, or `nil` if no adapter is
  configured or the adapter does not require a supervised process.
  """
  def worker_spec do
    case adapter() do
      nil -> nil
      mod -> mod.worker_spec()
    end
  end

  @doc """
  Retrieves a stored PDF. Returns `{:ok, binary}` on hit, `:miss` otherwise.
  """
  @spec get(String.t(), pos_integer(), String.t()) :: {:ok, binary()} | :miss
  def get(name, version, hash) do
    case adapter() do
      nil -> :miss
      mod ->
        case mod.get(name, version, hash) do
          {:ok, binary} -> {:ok, binary}
          :miss -> :miss
          {:error, _} -> :miss
        end
    end
  end

  @doc """
  Persists a rendered PDF binary. Failures are logged but do not propagate — the
  caller always receives the PDF regardless of whether storage succeeded.
  """
  @spec put(String.t(), pos_integer(), String.t(), binary()) :: :ok
  def put(name, version, hash, binary) do
    case adapter() do
      nil ->
        :ok

      mod ->
        case mod.put(name, version, hash, binary) do
          :ok ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "SferaDoc.Pdf.ObjectStore: failed to store PDF #{name}/#{version} — #{inspect(reason)}"
            )

            :ok
        end
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp adapter do
    Application.get_env(:sfera_doc, :pdf_object_store, [])[:adapter]
  end
end
