# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI do
  alias ExTTRPGDev.Dice
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.Abilities
  alias ExTTRPGDev.RuleSystems.Languages
  alias ExTTRPGDev.RuleSystems.Skills
  alias ExTTRPGDev.CustomParsers

  @moduledoc """
  The CLI for the project
  """

  def main(argv) do
    optimus =
      Optimus.new!(
        name: "ex_ttrpg_dev",
        description: "CLI for all things RPG",
        version: "0.5.0",
        author: "Quigley Malcolm quigley@quigleymalcolm.com",
        about: "Utility for playing tabletop role-playing games.",
        allow_unknown_args: false,
        parse_double_dash: true,
        subcommands: [
          roll: [
            name: "roll",
            about: "Roll some dice",
            args: [
              dice: [
                value_name: "DICE",
                help:
                  "Dice in the format of xdy wherein x is the number of dice, y is the number of sides the dice should have",
                required: true,
                parser: &CustomParsers.dice_parser(&1)
              ]
            ]
          ],
          list_systems: [
            name: "list-systems",
            about: "List systems that are setup to be used with ExTTRPGDev"
          ],
          system: [
            name: "system",
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
          ],
          gen: [
            name: "gen",
            about: "system agnostic generation helpers",
            subcommands: [
              name: [
                name: "name",
                about: "Generate a random name"
              ]
            ]
          ]
        ]
      )

    case Optimus.parse!(optimus, argv) do
      %{args: %{}} ->
        Optimus.parse!(optimus, ["--help"])

      {[:roll], parse_result} ->
        handle_roll(parse_result)

      {[:list_systems], _} ->
        RuleSystems.list_systems()
        |> IO.inspect(label: "Configured Systems")

      {[:system | sub_commands], parse_result} ->
        handle_system_subcommands(sub_commands, parse_result)

      {[:gen | sub_commands], _} ->
        handle_generate_subcommands(sub_commands)

      {unhandled, _parse_result} ->
        str_command =
          unhandled
          |> Enum.reduce([], fn x, acc -> [Atom.to_string(x) | acc] end)
          |> Enum.reverse()
          |> Enum.join(" ")

        raise "Unhandled CLI command `#{str_command}`, if you are seeing this error please report the issue"
    end
  end

  def handle_roll(%Optimus.ParseResult{args: %{dice: dice}}) do
    dice
    |> Dice.multi_roll!()
    |> Enum.each(fn {dice_spec, results} ->
      IO.inspect(results, label: dice_spec, charlists: :as_lists)
    end)
  end

  def handle_system_subcommands([command | subcommands], %Optimus.ParseResult{
        args: %{system: system}
      }) do
    loaded_system =
      system
      |> RuleSystems.assert_configured!()
      |> RuleSystems.load_system!()

    case command do
      :gen ->
        handle_system_generation_subcommands(subcommands, loaded_system)

      :show ->
        handle_system_show_subcommands(subcommands, loaded_system)
    end
  end

  def handle_system_generation_subcommands(
        [command | _subcommands],
        %RuleSystems.RuleSystem{} = system
      ) do
    case command do
      :stat_block ->
        RuleSystems.RuleSystem.gen_ability_scores_assigned(system)
        |> IO.inspect()

      :character ->
        character = Character.gen_character!(system)
        IO.puts("-- Name: #{character.name}")

        Enum.each(character.ability_scores, fn {ability, scores} ->
          IO.puts("#{ability}: #{Enum.sum(scores)}")
        end)
    end
  end

  def handle_system_show_subcommands(
        [command | _subcommands],
        %RuleSystems.RuleSystem{} = system
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

  def handle_generate_subcommands([command | _subcommands]) do
    case command do
      :name ->
        IO.inspect(Faker.Person.name())
    end
  end

  def show_abilities(%RuleSystems.RuleSystem{abilities: %Abilities{specs: specs}}) do
    Enum.each(specs, fn %Abilities.Spec{name: name, abbreviation: abbr} ->
      IO.puts("(#{abbr}) #{name}")
    end)
  end

  def show_languages(%RuleSystems.RuleSystem{languages: languages}) do
    Enum.each(languages, fn %Languages.Language{name: name, script: script} ->
      IO.puts("Name: #{name}, Script: #{script}")
    end)
  end

  def show_skills(%RuleSystems.RuleSystem{skills: skills} = system) do
    Enum.each(skills, fn %Skills.Skill{name: name, modifying_stat: mod_stat} ->
      %Abilities.Spec{abbreviation: abbr} =
        RuleSystems.RuleSystem.get_spec_by_name(system, mod_stat)

      IO.puts("(#{abbr}) #{name}")
    end)
  end
end
