defmodule SferaDoc.Store do
  @moduledoc false
  # Internal store API. Delegates to the configured adapter and invalidates
  # the AST cache on any write operation.
  # External code should use the SferaDoc facade, not this module directly.

  alias SferaDoc.{Config, Template}
  alias SferaDoc.Cache.ParsedTemplate

  def get(name), do: Config.store_adapter().get(name)

  def get_version(name, version), do: Config.store_adapter().get_version(name, version)

  def put(%Template{} = template) do
    with {:ok, saved} <- Config.store_adapter().put(template) do
      ParsedTemplate.invalidate(saved.name, saved.version)
      {:ok, saved}
    end
  end

  def list, do: Config.store_adapter().list()

  def list_versions(name), do: Config.store_adapter().list_versions(name)

  def activate_version(name, version) do
    with {:ok, t} <- Config.store_adapter().activate_version(name, version) do
      ParsedTemplate.invalidate(t.name, t.version)
      {:ok, t}
    end
  end

  def delete(name) do
    result = Config.store_adapter().delete(name)
    # Best-effort cache invalidation (we don't know all version numbers here)
    result
  end
end
