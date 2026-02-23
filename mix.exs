defmodule ExTtrpgDevUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.6.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  defp aliases do
    [
      escript: ["do --app ttrpg_dev_cli escript.build"]
    ]
  end

  defp deps, do: []
end
