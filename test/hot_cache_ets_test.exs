# defmodule SferaDoc.Pdf.HotCacheETSTest do
#   use ExUnit.Case, async: false

#   @moduletag :hot_cache

#   alias SferaDoc.Pdf.HotCache

#   @ets_table :sfera_doc_pdf_hot_cache

#   setup do
#     Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :ets, ttl: 2)

#     # Start fresh for each test
#     case Process.whereis(HotCache) do
#       nil ->
#         start_supervised!(HotCache)

#       pid ->
#         # Clear the ETS table between tests
#         :ets.delete_all_objects(@ets_table)
#         pid
#     end

#     on_exit(fn ->
#       Application.delete_env(:sfera_doc, :pdf_hot_cache)
#     end)

#     :ok
#   end

#   test "get returns :miss when entry does not exist" do
#     assert :miss = HotCache.get("my_template", 1, "abc123")
#   end

#   test "put and get returns the stored binary within TTL" do
#     pdf = <<1, 2, 3, 4, 5>>
#     assert :ok = HotCache.put("report", 1, "hash1", pdf)
#     assert {:ok, ^pdf} = HotCache.get("report", 1, "hash1")
#   end

#   test "get returns :miss for a different key" do
#     pdf = <<1, 2, 3>>
#     HotCache.put("report", 1, "hash1", pdf)

#     assert :miss = HotCache.get("report", 1, "different_hash")
#     assert :miss = HotCache.get("report", 2, "hash1")
#     assert :miss = HotCache.get("other", 1, "hash1")
#   end

#   test "get returns :miss after TTL expires" do
#     Application.put_env(:sfera_doc, :pdf_hot_cache, adapter: :ets, ttl: 1)

#     pdf = <<9, 8, 7>>
#     HotCache.put("doc", 3, "hashX", pdf)

#     # Still within TTL
#     assert {:ok, ^pdf} = HotCache.get("doc", 3, "hashX")

#     # Wait for TTL to expire (TTL is 1 second)
#     Process.sleep(1100)

#     assert :miss = HotCache.get("doc", 3, "hashX")
#   end

#   test "put overwrites an existing entry" do
#     HotCache.put("doc", 1, "hash", <<1, 2, 3>>)
#     HotCache.put("doc", 1, "hash", <<4, 5, 6>>)

#     assert {:ok, <<4, 5, 6>>} = HotCache.get("doc", 1, "hash")
#   end

#   test "get and put are no-ops when adapter is nil" do
#     Application.put_env(:sfera_doc, :pdf_hot_cache, [])

#     assert :miss = HotCache.get("x", 1, "h")
#     assert :ok = HotCache.put("x", 1, "h", <<1>>)
#   end
# end
