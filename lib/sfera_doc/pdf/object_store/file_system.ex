defmodule SferaDoc.Pdf.ObjectStore.FileSystem do
  @moduledoc """
  File-system backed PDF object storage.

  PDFs are written as regular files under a configurable base path, organized as:

      {path}/{prefix}{name}/{version}/{assigns_hash}.pdf

  No external dependencies are required.

  ## Configuration

      config :sfera_doc, :pdf_object_store,
        adapter: SferaDoc.Pdf.ObjectStore.FileSystem,
        path: "/var/data/pdfs",
        prefix: ""          # optional, default ""

  The `path` directory will be created automatically on first write.
  """

  @behaviour SferaDoc.Pdf.ObjectStore.Adapter

  require Logger

  @impl true
  def worker_spec, do: nil

  @impl true
  def get(name, version, hash) do
    path = file_path(name, version, hash)

    case File.read(path) do
      {:ok, binary} ->
        {:ok, binary}

      {:error, :enoent} ->
        :miss

      {:error, reason} ->
        Logger.warning(
          "SferaDoc.Pdf.ObjectStore.FileSystem: read failed (#{inspect(reason)}) for #{path}"
        )

        :miss
    end
  end

  @impl true
  def put(name, version, hash, binary) do
    path = file_path(name, version, hash)
    dir = Path.dirname(path)

    with :ok <- File.mkdir_p(dir),
         :ok <- File.write(path, binary) do
      :ok
    else
      {:error, reason} ->
        Logger.warning(
          "SferaDoc.Pdf.ObjectStore.FileSystem: write failed (#{inspect(reason)}) for #{path}"
        )

        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp file_path(name, version, hash) do
    opts = Application.get_env(:sfera_doc, :pdf_object_store, [])
    base = Keyword.fetch!(opts, :path)
    prefix = Keyword.get(opts, :prefix, "")
    Path.join([base, "#{prefix}#{name}", to_string(version), "#{hash}.pdf"])
  end
end
