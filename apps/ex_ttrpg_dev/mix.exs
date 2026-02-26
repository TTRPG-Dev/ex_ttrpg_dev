defmodule ExTTRPGDev.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_ttrpg_dev,
      version: "0.6.2",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      description: description(),
      package: package(),
      name: "ExTTRPGDev",
      source_url: "https://github.com/TTRPG-Dev/ex_ttrpg_dev",
      test_coverage: [tool: ExCoveralls]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:ex_doc, "~> 0.40", only: :dev, runtime: false},
      {:poison, "~> 6.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:faker, "~> 0.18"},
      {:toml_elixir, "~> 3.1"},
      {:abacus, "~> 2.1"},
      {:libgraph, "~> 0.16"}
    ]
  end

  defp description do
    "ExTTRPGDev is a general utility for tabletop role-playing games."
  end

  defp package do
    [
      licenses: ["GPL-3.0-only"],
      links: %{"GitHub" => "https://github.com/TTRPG-Dev/ex_ttrpg_dev"}
    ]
  end
end
