defmodule Ulam.MixProject do
  use Mix.Project

  def project do
    [
      app: :ulam,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  # Run "mix help compile.app" to learn about applications.
  def application do
    [
      extra_applications: [:logger]
    ]
  end

  # Run "mix help deps" to learn about dependencies.
  defp deps do
    [
      {:explorer, "~> 0.7"},
      {:jason, "~> 1.4"},
      {:owl, "~> 0.8"}
    ]
  end
end
