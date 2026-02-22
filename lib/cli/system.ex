# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI.RuleSystems do
  @moduledoc """
  Definitions for dealing with rule system CLI commands
  """
  alias ExTTRPGDev.CLI.Args
  alias ExTTRPGDev.RuleSystem.Expression
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
            about: "Used for showing information about the rule system",
            subcommands: [
              abilities: [
                name: "abilities",
                about: "Show the rule systems character abilities",
                args: Args.system()
              ],
              languages: [
                name: "languages",
                about: "Show the rule systems languages",
                args: Args.system()
              ],
              metadata: [
                name: "metadata",
                about: "Show system metadata",
                args: Args.system()
              ],
              skills: [
                name: "skills",
                about: "Show rule system skills",
                args: Args.system()
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

  def handle_systems_subcommands([:show | subcommands], %Optimus.ParseResult{
        args: %{system: system}
      }) do
    case subcommands do
      [:abilities] -> show_abilities(system)
      [:languages] -> show_languages(system)
      [:metadata] -> IO.inspect(system.package)
      [:skills] -> show_skills(system)
    end
  end

  @doc "Show a rule system's abilities"
  def show_abilities(%LoadedSystem{concept_metadata: meta}) do
    meta
    |> Enum.filter(fn {{type, _id}, _} -> type == "attr" end)
    |> Enum.sort_by(fn {{_type, id}, _} -> id end)
    |> Enum.each(fn {{_type, _id}, fields} ->
      IO.puts("(#{fields["abbreviation"]}) #{fields["name"]}")
    end)
  end

  @doc "Show a rule system's languages"
  def show_languages(%LoadedSystem{concept_metadata: meta}) do
    meta
    |> Enum.filter(fn {{type, _id}, _} -> type == "language" end)
    |> Enum.sort_by(fn {{_type, _id}, fields} -> fields["name"] end)
    |> Enum.each(fn {{_type, _id}, fields} ->
      script = Map.get(fields, "script", "none")
      IO.puts("#{fields["name"]} (script: #{script})")
    end)
  end

  @doc "Show a rule system's skills"
  def show_skills(%LoadedSystem{concept_metadata: meta, nodes: nodes}) do
    nodes
    |> Enum.filter(fn {{type, _id, field}, _} -> type == "skill" and field == "modifier" end)
    |> Enum.sort_by(fn {{_type, id, _field}, _} -> id end)
    |> Enum.each(fn {{_type, skill_id, _field}, %{formula: formula}} ->
      skill_name = get_in(meta, [{"skill", skill_id}, "name"]) || skill_id

      abbr =
        case Expression.extract_refs(formula) do
          [{attr_type, attr_id, _} | _] ->
            get_in(meta, [{attr_type, attr_id}, "abbreviation"]) || attr_id

          [] ->
            "?"
        end

      IO.puts("(#{abbr}) #{skill_name}")
    end)
  end
end
