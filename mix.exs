defmodule SferaDoc.MixProject do
  use Mix.Project

  @version "0.0.1"
  @source_url "https://github.com/sfera/sfera_doc"

  def project do
    [
      app: :sfera_doc,
      version: @version,
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      description: "PDF generation library with versioned Liquid templates stored in a database",
      package: package(),
      docs: docs()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :crypto],
      mod: {SferaDoc.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      # Always required
      {:solid, "~> 1.2"},
      {:telemetry, "~> 1.0"},
      {:jason, "~> 1.4"},

      # Optional storage backends
      {:ecto_sql, "~> 3.10", optional: true},
      {:postgrex, ">= 0.0.0", optional: true},
      {:ecto_sqlite3, ">= 0.0.0", optional: true},

      # Optional Redis backend
      {:redix, "~> 1.1", optional: true},

      # Optional PDF renderer
      {:chromic_pdf, "~> 1.14", optional: true},

      # Optional PDF object-store adapters
      {:ex_aws, "~> 2.5", optional: true},
      {:ex_aws_s3, "~> 2.5", optional: true},
      {:azurex, "~> 1.1", optional: true},

      # Dev/test
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp aliases do
    [
      "test.ets": ["test --only ets"],
      "test.ecto": [
        "ecto.create --quiet",
        "ecto.migrate --quiet",
        "test --only ecto"
      ],
      "test.redis": ["test --only redis"],
      "test.all": ["test.ets", "test.redis", "test.ecto"]
    ]
  end

  defp package do
    [
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "SferaDoc",
      source_ref: "v#{@version}",
      source_url: @source_url
    ]
  end
end
