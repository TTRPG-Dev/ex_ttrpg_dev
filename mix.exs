defmodule ExTTRPGDev.MixProject do
  use Mix.Project

  def project do
    [
      app: :ex_rpg,
      version: "0.2.1",
      elixir: "~> 1.13",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
      description: description(),
      package: package(),
      name: "ExTTRPGDev",
      source_url: "https://github.com/QMalcolm/ex_rpg"
    ]
  end

  def escript do
    [main_module: ExTTRPGDev.CLI]
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
      {:optimus, "~> 0.3"},
      {:ex_doc, "~> 0.27", only: :dev, runtime: false},
      {:poison, "~> 5.0"},
      {:credo, "~> 1.6", only: [:dev, :test], runtime: false}
      # {:dep_from_hexpm, "~> 0.3.0"},
      # {:dep_from_git, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
    ]
  end

  defp description() do
    "ExTTRPGDev is a general utility for tabletop role-playing games."
  end

  defp package() do
    [
      licenses: ["GPL-3.0-only"],
      links: %{"GitHub" => "https://github.com/QMalcolm/ex_rpg"}
    ]
  end
end
