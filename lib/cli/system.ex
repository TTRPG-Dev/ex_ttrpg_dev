# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI.RuleSystems do
  @moduledoc """
  Defintions for dealing with rule system CLI commands
  """
  alias ExTTRPGDev.CLI.Args
  alias ExTTRPGDev.RuleSystems.Abilities
  alias ExTTRPGDev.RuleSystems.Languages
  alias ExTTRPGDev.RuleSystems.RuleSystem
  alias ExTTRPGDev.RuleSystems.Skills

  @doc """
  Command specifications for rule system CLI commands
  """
  def commands do
    [
      systems: [
        name: "systems",
        about: "Top level command fo systems",
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
    ExTTRPGDev.RuleSystems.list_systems()
    |> IO.inspect(label: "Configured Systems")
  end

  def handle_systems_subcommands([command | subcommands], %Optimus.ParseResult{
        args: %{system: system}
      }) do
    case command do
      :show ->
        handle_system_show_subcommands(subcommands, system)
    end
  end

  @doc """
  Hand showing a rule system's components
  """
  def handle_system_show_subcommands(
        [command | _subcommands],
        %RuleSystem{} = system
      ) do
    case command do
      :abilities ->
        show_abilities(system)

      :languages ->
        show_languages(system)

      :metadata ->
        Map.get(system, :metadata)
        |> IO.inspect()

      :skills ->
        show_skills(system)
    end
  end

  @doc """
  Show a rule system's abilities
  """
  def show_abilities(%RuleSystem{abilities: %Abilities{specs: specs}}) do
    Enum.each(specs, fn %Abilities.Spec{name: name, abbreviation: abbr} ->
      IO.puts("(#{abbr}) #{name}")
    end)
  end

  @doc """
  Show a rule system's languages
  """
  def show_languages(%RuleSystem{languages: languages}) do
    Enum.each(languages, fn %Languages.Language{name: name, script: script} ->
      IO.puts("Name: #{name}, Script: #{script}")
    end)
  end

  @doc """
  Show a rule system's skills
  """
  def show_skills(%RuleSystem{skills: skills} = system) do
    Enum.each(skills, fn %Skills.Skill{name: name, modifying_stat: mod_stat} ->
      %Abilities.Spec{abbreviation: abbr} =
        RuleSystem.get_spec_by_name(system, mod_stat)

      IO.puts("(#{abbr}) #{name}")
    end)
  end
end
