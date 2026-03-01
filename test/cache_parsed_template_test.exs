# defmodule SferaDoc.Cache.ParsedTemplateTest do
#   use ExUnit.Case, async: false

#   alias SferaDoc.Cache.ParsedTemplate

#   setup do
#     # Ensure the GenServer is stopped between tests so we get a clean ETS table.
#     case Process.whereis(ParsedTemplate) do
#       nil -> :ok
#       pid -> GenServer.stop(pid)
#     end

#     :ok
#   end

#   describe "when cache is disabled" do
#     setup do
#       Application.put_env(:sfera_doc, :cache, enabled: false)
#       on_exit(fn -> Application.delete_env(:sfera_doc, :cache) end)
#     end

#     test "get/2 returns :miss without crashing" do
#       assert ParsedTemplate.get("tmpl", 1) == :miss
#     end

#     test "put/3 is a no-op and returns :ok" do
#       assert ParsedTemplate.put("tmpl", 1, :some_ast) == :ok
#     end

#     test "invalidate/2 is a no-op and returns :ok" do
#       assert ParsedTemplate.invalidate("tmpl", 1) == :ok
#     end

#     test "worker_spec/0 returns nil" do
#       assert ParsedTemplate.worker_spec() == nil
#     end
#   end

#   describe "when cache is enabled" do
#     setup do
#       Application.put_env(:sfera_doc, :cache, enabled: true, ttl: 300)
#       on_exit(fn -> Application.delete_env(:sfera_doc, :cache) end)

#       start_supervised!(ParsedTemplate)

#       :ok
#     end

#     test "get/2 returns :miss for unknown key" do
#       assert ParsedTemplate.get("no_such_template", 1) == :miss
#     end

#     test "put/3 and get/2 round-trip" do
#       ast = {:parsed, "Hello {{ name }}!"}
#       assert :ok = ParsedTemplate.put("welcome", 1, ast)
#       assert {:ok, ^ast} = ParsedTemplate.get("welcome", 1)
#     end

#     test "get/2 distinguishes different versions" do
#       ast_v1 = {:parsed, "v1"}
#       ast_v2 = {:parsed, "v2"}
#       ParsedTemplate.put("doc", 1, ast_v1)
#       ParsedTemplate.put("doc", 2, ast_v2)

#       assert {:ok, ^ast_v1} = ParsedTemplate.get("doc", 1)
#       assert {:ok, ^ast_v2} = ParsedTemplate.get("doc", 2)
#     end

#     test "invalidate/2 removes a specific entry" do
#       ParsedTemplate.put("tmpl", 1, :ast)
#       assert {:ok, :ast} = ParsedTemplate.get("tmpl", 1)

#       assert :ok = ParsedTemplate.invalidate("tmpl", 1)
#       assert :miss = ParsedTemplate.get("tmpl", 1)
#     end

#     test "invalidate/2 does not affect other entries" do
#       ParsedTemplate.put("tmpl", 1, :ast_v1)
#       ParsedTemplate.put("tmpl", 2, :ast_v2)
#       ParsedTemplate.invalidate("tmpl", 1)

#       assert :miss = ParsedTemplate.get("tmpl", 1)
#       assert {:ok, :ast_v2} = ParsedTemplate.get("tmpl", 2)
#     end

#     test "get/2 returns :miss after TTL expires" do
#       Application.put_env(:sfera_doc, :cache, enabled: true, ttl: 0)
#       ast = {:parsed, "old"}
#       ParsedTemplate.put("expired", 1, ast)

#       # TTL is 0 seconds, so any stored entry is immediately stale.
#       assert :miss = ParsedTemplate.get("expired", 1)
#     end

#     test "worker_spec/0 returns a valid child spec" do
#       spec = ParsedTemplate.worker_spec()
#       assert is_map(spec)
#       assert spec.id == ParsedTemplate
#       assert spec.restart == :permanent
#     end
#   end
# end
