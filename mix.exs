defmodule Legend.MixProject do
  use Mix.Project

  @in_production Mix.env() == :prod
  @version "0.0.1"
  @author "naramore"
  @source_url "https://github.com/naramore/legend"
  @description """
  Sagas pattern implementation in Elixir.
  """

  def project do
    [
      app: :legend,
      version: @version,
      elixir: "~> 1.7",
      elixirc_paths: elixirc_paths(Mix.env()),
      compilers: Mix.compilers(),
      build_embedded: @in_production,
      start_permanent: @in_production,
      deps: deps(),
      aliases: aliases(),

      # Hex
      description: @description,
      package: package(),

      # Docs
      name: "Legend",
      docs: docs(),

      # Custom testing
      test_coverage: [tool: ExCoveralls],
      preferred_cli_env: [coveralls: :test, "coveralls.html": :test],
      dialyzer: [ignore_warnings: ".dialyzer.ignore-warnings"]
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:ex_doc, "~> 0.19", only: [:dev, :test]},
      {:dialyxir, "~> 0.5", only: [:dev, :test]},
      {:propcheck, "~> 1.1", only: [:dev, :test]},
      {:inch_ex, github: "rrrene/inch_ex", only: [:dev, :test]},
      {:benchfella, "~> 0.3", only: [:dev, :test]},
      {:excoveralls, "~> 0.10", only: [:dev, :test]},
    ]
  end

  defp package do
    [
      contributors: [@author],
      maintainers: [@author],
      source_ref: "v#{@version}",
      links: %{"GitHub" => @source_url},
      files: ~w(mix.exs .formatter.exs lib README.md)
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: ["README.md"]
    ]
  end

  defp aliases do
    []
  end
end
