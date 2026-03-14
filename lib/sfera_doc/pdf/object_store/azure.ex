defmodule SferaDoc.Pdf.ObjectStore.Azure do
  @moduledoc """
  Azure Blob Storage PDF object store.

  Requires the optional dependency `:azurex`.

  ## Configuration

      config :sfera_doc, :pdf_object_store,
        adapter: SferaDoc.Pdf.ObjectStore.Azure,
        container: "my-pdfs",
        prefix: "sfera_doc/"   # optional, default ""

  Credentials must be configured via the `azurex` global configuration:

      config :azurex, Azurex.Blob.Config,
        storage_account_name: "mystorageaccount",
        storage_account_key: "base64encodedkey=="

  For local development with Azurite, configure the API URL:

      config :azurex, Azurex.Blob.Config,
        storage_account_name: "devstoreaccount1",
        storage_account_key: "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw==",
        api_url: "http://127.0.0.1:10000/devstoreaccount1"

  ## Blob name format

      {prefix}{name}/{version}/{assigns_hash}.pdf
  """

  @behaviour SferaDoc.Pdf.ObjectStore.Adapter

  require Logger

  @impl true
  def worker_spec, do: nil

  @impl true
  def get(name, version, hash) do
    ensure_deps!()
    opts = Application.get_env(:sfera_doc, :pdf_object_store, [])
    blob = blob_name(name, version, hash, opts)
    container = Keyword.fetch!(opts, :container)

    case apply(Azurex.Blob, :get_blob, [blob, container]) do
      {:ok, body} ->
        {:ok, body}

      {:error, %{status: 404}} ->
        :miss

      {:error, reason} ->
        Logger.warning(
          "SferaDoc.Pdf.ObjectStore.Azure: get failed (#{inspect(reason)}) for #{blob}"
        )

        :miss
    end
  end

  @impl true
  def put(name, version, hash, binary) do
    ensure_deps!()
    opts = Application.get_env(:sfera_doc, :pdf_object_store, [])
    blob = blob_name(name, version, hash, opts)
    container = Keyword.fetch!(opts, :container)

    case apply(Azurex.Blob, :put_blob, [blob, binary, "application/pdf", container]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "SferaDoc.Pdf.ObjectStore.Azure: put failed (#{inspect(reason)}) for #{blob}"
        )

        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp blob_name(name, version, hash, opts) do
    prefix = Keyword.get(opts, :prefix, "")
    "#{prefix}#{name}/#{version}/#{hash}.pdf"
  end

  defp ensure_deps! do
    unless Code.ensure_loaded?(Azurex.Blob) do
      raise """
      SferaDoc.Pdf.ObjectStore.Azure requires the :azurex dependency.
      Add to your mix.exs:

          {:azurex, "~> 1.1"}
      """
    end
  end
end
