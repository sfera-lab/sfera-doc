defmodule SferaDoc.Cache.RenderedPdf do
  @moduledoc """
  Optional Redis-backed cache for rendered PDF binaries.

  > #### Memory Warning {: .warning}
  >
  > PDF files can be 100 KB to 10 MB or more. Caching them in Redis without
  > appropriate TTLs and eviction policies can exhaust Redis memory. Before
  > enabling this cache:
  >
  > - Set a short, explicit TTL (e.g. 60 seconds)
  > - Configure Redis `maxmemory-policy allkeys-lru`
  > - Monitor Redis memory consumption in production
  >
  > ETS is intentionally **not** supported for PDF caching to avoid BEAM OOM.

  **Disabled by default.** Enable via:

      config :sfera_doc, :pdf_cache,
        enabled: true,
        ttl: 60   # seconds

  **Requires the Redis store adapter.** This cache reuses the connection
  started by `SferaDoc.Store.Redis`.

  ## Cache Key

  The cache key includes the template name, version, and an MD5 hash of the
  assigns map so different variable values produce different cache entries.
  """

  @prefix "sfera_doc:pdf"

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Returns `{:ok, pdf_binary}` on a cache hit, `:miss` otherwise.
  Always returns `:miss` when PDF caching is disabled.
  """
  @spec get(String.t(), pos_integer(), map()) :: {:ok, binary()} | :miss
  def get(name, version, assigns) do
    if SferaDoc.Config.pdf_cache_enabled?() do
      key = cache_key(name, version, assigns)

      case Redix.command(conn(), ["GET", key]) do
        {:ok, nil} -> :miss
        {:ok, binary} -> {:ok, binary}
        {:error, _} -> :miss
      end
    else
      :miss
    end
  end

  @doc """
  Stores a rendered PDF in the Redis cache with the configured TTL.
  No-op when PDF caching is disabled.
  """
  @spec put(String.t(), pos_integer(), map(), binary()) :: :ok
  def put(name, version, assigns, pdf_binary) do
    if SferaDoc.Config.pdf_cache_enabled?() do
      ttl = SferaDoc.Config.pdf_cache_ttl()
      key = cache_key(name, version, assigns)

      case Redix.command(conn(), ["SET", key, pdf_binary, "EX", ttl]) do
        {:ok, _} -> :ok
        {:error, _} -> :ok
      end
    else
      :ok
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp cache_key(name, version, assigns) do
    hash =
      assigns
      |> :erlang.term_to_binary()
      |> then(&:crypto.hash(:md5, &1))
      |> Base.encode16(case: :lower)

    "#{@prefix}:#{name}:#{version}:#{hash}"
  end

  defp conn do
    if SferaDoc.Config.store_adapter() == SferaDoc.Store.Redis do
      SferaDoc.Store.Redis
    else
      raise """
      SferaDoc: PDF cache requires the Redis store adapter.
      Either disable PDF caching or switch to the Redis adapter:

          config :sfera_doc, :store, adapter: SferaDoc.Store.Redis
      """
    end
  end
end
