IO.puts("You are in development mode")


persistence = System.get_env("STORAGE_ADAPTER")

cond do

  persistence == "ecto" ->
    IO.puts("Using Ecto store adapter")
    SferaDoc.Dev.Repo.start_link()

  true ->
    IO.puts("storage adapter not set")
end
