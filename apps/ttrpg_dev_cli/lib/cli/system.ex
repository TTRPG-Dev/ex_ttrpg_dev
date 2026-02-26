# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI.RuleSystems do
  @moduledoc """
  Definitions for dealing with rule system CLI commands
  """
  alias ExTTRPGDev.CLI.Args
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Command specifications for rule system CLI commands
  """
  def commands do
    [
      systems: [
        name: "systems",
        about: "Top level command for systems",
        subcommands: [
          list: [
            name: "list",
            about: "List systems that ex_ttrpg_dev knows about"
          ],
          show: [
            name: "show",
            about: "Show metadata and concept types for a rule system",
            args: Args.system()
          ]
        ]
      ]
    ]
  end

  @doc """
  Handle `systems` CLI command and sub commands
  """
  def handle_systems_subcommands([:list], _) do
    case ExTTRPGDev.RuleSystems.list_systems() do
      [] ->
        IO.puts("No configured systems found.")

      systems ->
        IO.puts("Configured Systems:")
        Enum.each(systems, &IO.puts("- #{&1}"))
    end
  end

  def handle_systems_subcommands([:show], %Optimus.ParseResult{
        args: %{system: system}
      }) do
    show_system(system)
  end

  defp show_system(%LoadedSystem{module: mod}) do
    IO.puts("Name: #{mod.name}")
    IO.puts("Slug: #{mod.slug}")
    IO.puts("Version: #{mod.version}")
    if mod.publisher, do: IO.puts("Publisher: #{mod.publisher}")
    if mod.family, do: IO.puts("Family: #{mod.family}")
    if mod.series, do: IO.puts("Series: #{mod.series}")

    IO.puts("\nConcept Types:")

    Enum.each(mod.concept_types, fn ct ->
      IO.puts("  #{ct.id}: #{ct.name}")
    end)
  end
end
