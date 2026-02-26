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
            args: Args.system(),
            options: [
              concept_type: [
                value_name: "CONCEPT_TYPE",
                help: "Show all concepts belonging to the given concept type",
                long: "--concept-type",
                required: false
              ]
            ]
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
        args: %{system: system},
        options: options
      }) do
    case Map.get(options, :concept_type) do
      nil -> show_system(system)
      concept_type -> show_concepts(system, concept_type)
    end
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

  defp show_concepts(%LoadedSystem{concept_metadata: meta}, concept_type) do
    concepts =
      meta
      |> Enum.filter(fn {{type, _id}, _} -> type == concept_type end)
      |> Enum.sort_by(fn {{_type, id}, _} -> id end)

    if concepts == [] do
      IO.puts("No concepts found for concept type \"#{concept_type}\".")
    else
      Enum.each(concepts, fn {{_type, id}, fields} ->
        name = Map.get(fields, "name", id)
        IO.puts("#{id}: #{name}")
      end)
    end
  end
end
