# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI.RuleSystems do
  @moduledoc """
  Defintions for dealing with rule system CLI commands
  """
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystems.Abilities
  alias ExTTRPGDev.RuleSystems.Languages
  alias ExTTRPGDev.RuleSystems.RuleSystem
  alias ExTTRPGDev.RuleSystems.Skills

  @doc """
  Command specifications for rule system CLI commands
  """
  def commands do
    [
      list_systems: [
        name: "list-systems",
        about: "List systems that are setup to be used with ExTTRPGDev"
      ],
      systems: [
        name: "systems",
        about: "Top level command fo systems",
        subcommands: [
          gen: [
            name: "gen",
            about: "Used for generating things for the system",
            subcommands: [
              stat_block: [
                name: "stat-block",
                about: "Generate stat blocks for characters of the system",
                args: [
                  system: [
                    value_name: "SYSTEM",
                    help: "A supported system, e.g. dnd5e",
                    required: true,
                    parser: :string
                  ]
                ]
              ],
              character: [
                name: "character",
                about: "Generate characters for system",
                args: [
                  system: [
                    value_name: "SYSTEM",
                    help: "A supported system, e.g. dnd5e",
                    required: true,
                    parser: :string
                  ]
                ]
              ]
            ]
          ],
          show: [
            name: "show",
            about: "Used for showing information about the rule system",
            subcommands: [
              abilities: [
                name: "abilities",
                about: "Show the rule systems character abilities",
                args: [
                  system: [
                    value_name: "SYSTEM",
                    help: "A supported system, e.g. dnd5e",
                    required: true,
                    parser: :string
                  ]
                ]
              ],
              languages: [
                name: "languages",
                about: "Show the rule systems languages",
                args: [
                  system: [
                    value_name: "SYSTEM",
                    help: "A supported system, e.g. dnd5e",
                    required: true,
                    parser: :string
                  ]
                ]
              ],
              metadata: [
                name: "metadata",
                about: "Show system metadata",
                args: [
                  system: [
                    value_name: "SYSTEM",
                    help: "A supported system, e.g. dnd5e",
                    required: true,
                    parser: :string
                  ]
                ]
              ],
              skills: [
                name: "skills",
                about: "Show rule system skills",
                args: [
                  system: [
                    value_name: "SYSTEM",
                    help: "A supported system, e.g. dnd5e",
                    required: true,
                    parser: :string
                  ]
                ]
              ]
            ]
          ]
        ]
      ]
    ]
  end

  @doc """
  Handle list-systems CLI command
  """
  def handle_list_systems() do
    ExTTRPGDev.RuleSystems.list_systems()
    |> IO.inspect(label: "Configured Systems")
  end

  @doc """
  Handle `systems` CLI command and sub commands
  """
  def handle_systems_subcommands([command | subcommands], %Optimus.ParseResult{
        args: %{system: system}
      }) do
    loaded_system =
      system
      |> ExTTRPGDev.RuleSystems.assert_configured!()
      |> ExTTRPGDev.RuleSystems.load_system!()

    case command do
      :gen ->
        handle_system_generation_subcommands(subcommands, loaded_system)

      :show ->
        handle_system_show_subcommands(subcommands, loaded_system)
    end
  end

  @doc """
  Handle generation commands for a rule system
  """
  def handle_system_generation_subcommands(
        [command | _subcommands],
        %RuleSystem{} = system
      ) do
    case command do
      :stat_block ->
        RuleSystem.gen_ability_scores_assigned(system)
        |> IO.inspect()

      :character ->
        character = Character.gen_character!(system)
        IO.puts("-- Name: #{character.name}")

        Enum.each(character.ability_scores, fn {ability, scores} ->
          IO.puts("#{ability}: #{Enum.sum(scores)}")
        end)
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
