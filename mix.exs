defmodule ExTtrpgDevUmbrella.MixProject do
  use Mix.Project

  def project do
    [
      apps_path: "apps",
      version: "0.7.0",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases(),
      releases: releases(),
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

  defp releases do
    [
      ttrpg_dev_cli: [
        applications: [ttrpg_dev_cli: :permanent],
        steps: [:assemble, &Burrito.wrap/1],
        burrito: [
          # Set TTRPG_DEV_DEBUG=true at build time to enable verbose Burrito
          # startup output in the resulting binary (Zig debug log level).
          debug: System.get_env("TTRPG_DEV_DEBUG") == "true",
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
      {:burrito, "~> 1.0"},
      {:excoveralls, "~> 0.18", only: :test}
    ]
  end
end
