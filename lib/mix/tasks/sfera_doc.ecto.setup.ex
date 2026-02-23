defmodule Mix.Tasks.SferaDoc.Ecto.Setup do
  @shortdoc "Generates a migration for the sfera_doc_templates table"

  @moduledoc """
  Generates a migration file for the `sfera_doc_templates` table.

  This task creates a migration in your app's `priv/repo/migrations` directory
  that you can then run with `mix ecto.migrate`.

  ## Usage

      mix sfera_doc.ecto.setup

  ## Example Output

      Creating priv/repo/migrations/20240101120000_create_sfera_doc_templates.exs
  """

  use Mix.Task

  @impl Mix.Task
  def run(_args) do
    Mix.Task.run("app.config")

    repo =
      try do
        SferaDoc.Config.ecto_repo()
      rescue
        _ ->
          Mix.raise(
            "SferaDoc: no Ecto repo configured. Add to your config:\n\n" <>
              "    config :sfera_doc, :store,\n" <>
              "      adapter: SferaDoc.Store.Ecto,\n" <>
              "      repo: MyApp.Repo\n"
          )
      end

    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d%H%M%S")
    repo_path = repo |> Module.split() |> List.last() |> Macro.underscore()
    migrations_path = Path.join(["priv", repo_path, "migrations"])
    filename = "#{timestamp}_create_sfera_doc_templates.exs"
    filepath = Path.join(migrations_path, filename)

    repo_name = repo |> Module.split() |> Enum.join(".")

    content = """
    defmodule #{repo_name}.Migrations.CreateSferaDocTemplates do
      use SferaDoc.Store.Ecto.Migration
    end
    """

    File.mkdir_p!(migrations_path)
    File.write!(filepath, content)
    Mix.shell().info("Creating #{filepath}")
    Mix.shell().info("Run `mix ecto.migrate` to apply the migration.")
  end
end
