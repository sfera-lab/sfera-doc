defmodule SferaDoc.Pdf.ObjectStore.Azure do
  @moduledoc """
  Azure Blob Storage PDF object store.

  Requires the optional dependency `:azurex`.

  ## Configuration

      config :sfera_doc, :pdf_object_store,
        adapter: SferaDoc.Pdf.ObjectStore.Azure,
        container: "my-pdfs",
        prefix: "sfera_doc/"   # optional, default ""

  Credentials are read from the standard `azurex` configuration:

      config :azurex, Azurex.Blob.Config,
        storage_account_name: "mystorageaccount",
        storage_account_key: "base64encodedkey=="

  Alternatively, pass them inline (overrides global config):

      config :sfera_doc, :pdf_object_store,
        adapter: SferaDoc.Pdf.ObjectStore.Azure,
        container: "my-pdfs",
        storage_account_name: "mystorageaccount",
        storage_account_key: "base64encodedkey=="

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
    blob = blob_name(name, version, hash)
    opts = Application.get_env(:sfera_doc, :pdf_object_store, [])
    azurex_opts = azurex_opts(opts)

    case apply(Azurex.Blob, :get_blob, [blob, azurex_opts]) do
      {:ok, body} ->
        {:ok, body}

      {:error, %{status: 404}} ->
        :miss

      {:error, reason} ->
        Logger.warning("SferaDoc.Pdf.ObjectStore.Azure: get failed (#{inspect(reason)}) for #{blob}")
        :miss
    end
  end

  @impl true
  def put(name, version, hash, binary) do
    ensure_deps!()
    blob = blob_name(name, version, hash)
    opts = Application.get_env(:sfera_doc, :pdf_object_store, [])
    azurex_opts = azurex_opts(opts)

    case apply(Azurex.Blob, :put_blob, [blob, binary, "application/pdf", azurex_opts]) do
      :ok ->
        :ok

      {:error, reason} ->
        Logger.warning("SferaDoc.Pdf.ObjectStore.Azure: put failed (#{inspect(reason)}) for #{blob}")
        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp blob_name(name, version, hash) do
    opts = Application.get_env(:sfera_doc, :pdf_object_store, [])
    prefix = Keyword.get(opts, :prefix, "")
    "#{prefix}#{name}/#{version}/#{hash}.pdf"
  end

  # Build per-request azurex options from the sfera_doc config.
  # Passes container and any credential overrides; omits sfera_doc-specific keys.
  defp azurex_opts(opts) do
    container = Keyword.fetch!(opts, :container)
    base = [container: container]

    credential_keys = [:storage_account_name, :storage_account_key,
                       :storage_account_connection_string]

    Enum.reduce(credential_keys, base, fn key, acc ->
      case Keyword.fetch(opts, key) do
        {:ok, val} -> Keyword.put(acc, key, val)
        :error -> acc
      end
    end)
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
