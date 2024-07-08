defmodule Ulam.MixProject do
  use Mix.Project

  def project do
    [
      app: :ulam,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      elixirc_paths: elixirc_paths(Mix.env())
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib/", "test/support"]
  defp elixirc_paths(_env), do: ["lib/"]

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:explorer, "~> 0.8"},
      {:jason, "~> 1.4"},
      {:owl, "~> 0.8"},
      {:rustler, "~> 0.31", override: true, optional: true},
      {:stream_data, "~> 0.6", only: [:test, :dev]},
      {:benchee, "~> 1.0", only: [:dev, :test]},
      {:incendium, path: "../incendium", only: [:dev, :test]},
      {:statistics, "~> 0.6"},
      {:slugify, "~> 1.3"}
    ]
  end
end
