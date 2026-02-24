defmodule ExTtrpgDevUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.6.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases()
    ]
  end

  defp releases do
    [
      ttrpg_dev_cli: [
        applications: [ttrpg_dev_cli: :permanent],
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          # Set BURRITO_DEBUG=1 at build time to force a clean unpack on
          # every run (used by scripts/build_cli.sh for local testing).
          debug: System.get_env("BURRITO_DEBUG") == "1",
          targets: [
            linux: [os: :linux, cpu: :x86_64],
            macos: [os: :darwin, cpu: :x86_64],
            macos_arm: [os: :darwin, cpu: :aarch64],
            windows: [os: :windows, cpu: :x86_64]
          ]
        ]
      ]
    ]
  end

  defp aliases do
    [
      escript: ["do --app ttrpg_dev_cli escript.build"]
    ]
  end

  defp deps do
    [
      {:burrito, "~> 1.0"}
    ]
  end
end
