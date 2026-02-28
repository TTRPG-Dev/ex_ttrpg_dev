defmodule TtrpgDevCli.MixProject do
  use Mix.Project

  def project do
    [
      app: :ttrpg_dev_cli,
      version: "0.7.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      escript: escript(),
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

  def escript do
    [main_module: ExTTRPGDev.CLI, include_priv: [:ex_ttrpg_dev]]
  end

  def application do
    base = [extra_applications: [:logger]]

    if Mix.env() == :prod do
      Keyword.put(base, :mod, {TtrpgDevCli.Application, []})
    else
      base
    end
  end

  defp deps do
    [
      {:ex_ttrpg_dev, in_umbrella: true},
      {:optimus, "~> 0.6"},
      {:burrito, "~> 1.0"},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false}
    ]
  end
end
