defmodule SferaDoc.Pdf.ObjectStore.S3 do
  @moduledoc """
  Amazon S3 (or S3-compatible) PDF object storage.

  Requires the optional dependencies `:ex_aws` and `:ex_aws_s3`.

  ## Configuration

      config :sfera_doc, :pdf_object_store,
        adapter: SferaDoc.Pdf.ObjectStore.S3,
        bucket: "my-pdfs",
        prefix: "sfera_doc/",   # optional, default ""
        ex_aws: []              # optional ExAws.request/2 opts (e.g. region)

  ExAws credentials and region are read from the standard ExAws configuration
  (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, etc.).

  ## Object key format

      {prefix}{name}/{version}/{assigns_hash}.pdf
  """

  @behaviour SferaDoc.Pdf.ObjectStore.Adapter

  require Logger

  @impl true
  def worker_spec, do: nil

  @impl true
  def get(name, version, hash) do
    ensure_deps!()
    key = object_key(name, version, hash)
    opts = Application.get_env(:sfera_doc, :pdf_object_store, [])
    bucket = Keyword.fetch!(opts, :bucket)
    ex_aws_opts = Keyword.get(opts, :ex_aws, [])

    req = apply(ExAws.S3, :get_object, [bucket, key])

    case apply(ExAws, :request, [req, ex_aws_opts]) do
      {:ok, %{body: body}} ->
        {:ok, body}

      {:error, {:http_error, 404, _}} ->
        :miss

      {:error, reason} ->
        Logger.warning(
          "SferaDoc.Pdf.ObjectStore.S3: get failed (#{inspect(reason)}) for s3://#{bucket}/#{key}"
        )

        :miss
    end
  end

  @impl true
  def put(name, version, hash, binary) do
    ensure_deps!()
    key = object_key(name, version, hash)
    opts = Application.get_env(:sfera_doc, :pdf_object_store, [])
    bucket = Keyword.fetch!(opts, :bucket)
    ex_aws_opts = Keyword.get(opts, :ex_aws, [])

    req = apply(ExAws.S3, :put_object, [bucket, key, binary, [content_type: "application/pdf"]])

    case apply(ExAws, :request, [req, ex_aws_opts]) do
      {:ok, _} ->
        :ok

      {:error, reason} ->
        Logger.warning(
          "SferaDoc.Pdf.ObjectStore.S3: put failed (#{inspect(reason)}) for s3://#{bucket}/#{key}"
        )

        {:error, reason}
    end
  end

  # ---------------------------------------------------------------------------
  # Private
  # ---------------------------------------------------------------------------

  defp object_key(name, version, hash) do
    opts = Application.get_env(:sfera_doc, :pdf_object_store, [])
    prefix = Keyword.get(opts, :prefix, "")
    "#{prefix}#{name}/#{version}/#{hash}.pdf"
  end

  defp ensure_deps! do
    unless Code.ensure_loaded?(ExAws) and Code.ensure_loaded?(ExAws.S3) do
      raise """
      SferaDoc.Pdf.ObjectStore.S3 requires the :ex_aws and :ex_aws_s3 dependencies.
      Add to your mix.exs:

          {:ex_aws, "~> 2.5"},
          {:ex_aws_s3, "~> 2.5"}
      """
    end
  end
end
