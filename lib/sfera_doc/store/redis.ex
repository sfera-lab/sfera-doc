defmodule SferaDoc.Store.Redis do
  @moduledoc """
  Redis-backed storage adapter for SferaDoc.

  Uses `Redix` for communication. Starts and owns its own Redis connection
  within the SferaDoc supervision tree.

  ## Configuration

      config :sfera_doc, :store,
        adapter: SferaDoc.Store.Redis

      # Redis connection options (host/port or URI)
      config :sfera_doc, :redis,
        host: "localhost",
        port: 6379

      # Or with a URI:
      config :sfera_doc, :redis, "redis://localhost:6379"

  ## Key Schema

  Templates are stored under the following Redis keys:

  - `sfera_doc:template:{name}:version:{n}` — JSON of the full template
  - `sfera_doc:template:{name}:active` — active version number (string)
  - `sfera_doc:template:{name}:versions` — sorted set of all version numbers

  All template names are tracked in `sfera_doc:names` (a Redis set).
  """

  @behaviour SferaDoc.Store.Adapter

  @conn __MODULE__
  @prefix "sfera_doc"
  @names_key "#{@prefix}:names"

  # ---------------------------------------------------------------------------
  # Adapter callbacks
  # ---------------------------------------------------------------------------

  @impl SferaDoc.Store.Adapter
  def worker_spec do
    opts = SferaDoc.Config.redis_config()

    conn_opts =
      if is_list(opts), do: Keyword.merge(opts, name: @conn), else: [name: @conn, url: opts]

    Redix.child_spec(conn_opts)
  end

  @impl SferaDoc.Store.Adapter
  def get(name) do
    with {:ok, raw_version} <- Redix.command(@conn, ["GET", active_key(name)]),
         version when not is_nil(version) <- raw_version,
         {:ok, json} <- Redix.command(@conn, ["GET", template_key(name, version)]),
         json when not is_nil(json) <- json do
      {:ok, decode_template(json)}
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl SferaDoc.Store.Adapter
  def get_version(name, version) do
    case Redix.command(@conn, ["GET", template_key(name, to_string(version))]) do
      {:ok, nil} -> {:error, :not_found}
      {:ok, json} -> {:ok, decode_template(json)}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl SferaDoc.Store.Adapter
  def put(template) do
    with {:ok, next_v} <- next_version(template.name) do
      new_template = %{template | version: next_v, is_active: true}
      json = encode_template(new_template)
      v_str = to_string(next_v)

      commands = [
        ["MULTI"],
        ["SET", template_key(template.name, v_str), json],
        ["SET", active_key(template.name), v_str],
        ["ZADD", versions_key(template.name), v_str, v_str],
        ["SADD", @names_key, template.name],
        ["EXEC"]
      ]

      case Redix.pipeline(@conn, commands) do
        {:ok, _} -> {:ok, new_template}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @impl SferaDoc.Store.Adapter
  def list do
    with {:ok, names} <- Redix.command(@conn, ["SMEMBERS", @names_key]) do
      templates =
        names
        |> Enum.map(&get/1)
        |> Enum.flat_map(fn
          {:ok, t} -> [t]
          _ -> []
        end)
        |> Enum.sort_by(& &1.name)

      {:ok, templates}
    end
  end

  @impl SferaDoc.Store.Adapter
  def list_versions(name) do
    with {:ok, versions} <- Redix.command(@conn, ["ZRANGE", versions_key(name), 0, -1]) do
      templates =
        versions
        |> Enum.map(fn v ->
          case Redix.command(@conn, ["GET", template_key(name, v)]) do
            {:ok, json} when not is_nil(json) -> decode_template(json)
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.version, :desc)

      {:ok, templates}
    end
  end

  @impl SferaDoc.Store.Adapter
  def activate_version(name, version) do
    v_str = to_string(version)

    case Redix.command(@conn, ["GET", template_key(name, v_str)]) do
      {:ok, nil} ->
        {:error, :not_found}

      {:ok, json} ->
        template = decode_template(json)
        updated = %{template | is_active: true}

        commands = [
          ["MULTI"],
          ["SET", template_key(name, v_str), encode_template(updated)],
          ["SET", active_key(name), v_str],
          ["EXEC"]
        ]

        case Redix.pipeline(@conn, commands) do
          {:ok, _} -> {:ok, updated}
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  @impl SferaDoc.Store.Adapter
  def delete(name) do
    with {:ok, versions} <- Redix.command(@conn, ["ZRANGE", versions_key(name), 0, -1]) do
      template_keys = Enum.map(versions, &template_key(name, &1))

      keys_to_delete =
        template_keys ++ [active_key(name), versions_key(name)]

      commands = [
        ["MULTI"],
        ["DEL" | keys_to_delete],
        ["SREM", @names_key, name],
        ["EXEC"]
      ]

      case Redix.pipeline(@conn, commands) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp template_key(name, version), do: "#{@prefix}:template:#{name}:version:#{version}"
  defp active_key(name), do: "#{@prefix}:template:#{name}:active"
  defp versions_key(name), do: "#{@prefix}:template:#{name}:versions"

  defp next_version(name) do
    case Redix.command(@conn, ["ZRANGE", versions_key(name), -1, -1]) do
      {:ok, []} -> {:ok, 1}
      {:ok, [v]} -> {:ok, String.to_integer(v) + 1}
      {:error, reason} -> {:error, reason}
    end
  end

  defp encode_template(%SferaDoc.Template{} = t) do
    t
    |> Map.from_struct()
    |> Map.update(:inserted_at, nil, &datetime_to_string/1)
    |> Map.update(:updated_at, nil, &datetime_to_string/1)
    |> Jason.encode!()
  end

  defp decode_template(json) do
    data = Jason.decode!(json, keys: :atoms)

    %SferaDoc.Template{
      id: data[:id],
      name: data[:name],
      body: data[:body],
      version: data[:version],
      is_active: data[:is_active],
      variables_schema: data[:variables_schema],
      inserted_at: parse_datetime(data[:inserted_at]),
      updated_at: parse_datetime(data[:updated_at])
    }
  end

  defp datetime_to_string(nil), do: nil
  defp datetime_to_string(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime_to_string(other), do: other

  defp parse_datetime(nil), do: nil

  defp parse_datetime(str) when is_binary(str) do
    case DateTime.from_iso8601(str) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end

  defp parse_datetime(other), do: other
end
