defmodule ExRPG.CLI do
  alias ExRPG.Dice
  alias ExRPG.RuleSystems
  @moduledoc """
  The CLI for the project
  """

  def main(argv) do
    optimus = Optimus.new!(
      name: "ex_rpg",
      description: "CLI for all things RPG",
      version: "0.1.0",
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
              help: "Dice in the format of xdy wherein x is the number of dice, y is the number of sides the dice should have",
              required: true,
              parser: :string
            ]
          ]
        ],
        list_systems: [
          name: "list-systems",
          about: "List systems that are setup to be used with ExRPG",
        ],
        system: [
          name: "system",
          about: "Top level command fo systems",
          subcommands: [
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
              ]
            ]
          ]
        ],
      ]
    )

    case Optimus.parse!(optimus, argv) do
      %{args: %{}} ->
        Optimus.parse!(optimus, ["--help"])

      {[:roll], parse_result} ->
        handle_roll(parse_result)

      {[:gen, sub_command], parse_result} ->
        handle_generators(sub_command, parse_result)

      {[:list_systems], _} ->
        RuleSystems.list_systems()
        |> IO.inspect(label: "Configured Systems")

      {[:system | sub_commands], parse_result} ->
        handle_system_subcommands(sub_commands, parse_result)

      {unhandled, _parse_result} ->
        str_command = unhandled
          |> Enum.reduce([], fn x, acc -> [Atom.to_string(x) | acc ] end)
          |> Enum.reverse()
          |> Enum.join(" ")

        raise "Unhandled CLI command `#{str_command}`, if you are seeing this error please report the issue"
    end
  end

  def handle_roll(%Optimus.ParseResult{args: %{dice: dice_str}}) do
    Dice.roll(dice_str)
    |> IO.inspect(label: "Results")
  end

  def handle_generators(subcommand, %Optimus.ParseResult{} = parse_result) do
    case subcommand do
      :stat_block ->
        handle_stat_block(parse_result)

    end
  end

  def handle_stat_block(%Optimus.ParseResult{args: %{system: system_str}}) do
    case system_str do
      "dnd5e" ->
        DungoneAndDragons5e.Abilities.gen_scores()
        |> IO.inspect()

      _ ->
        IO.puts "Stat block generation is not currently supported for #{system_str}"
    end
  end

  def handle_system_subcommands([command | subcommands], %Optimus.ParseResult{args: %{system: system}}) do
    loaded_system = system
    |> RuleSystems.assert_configured!()
    |> RuleSystems.load_system!()

    case command do
      :metadata ->
        Map.get(loaded_system, :metadata)
        |> IO.inspect()

      :gen ->
        handle_system_generation_subcommands(subcommands, loaded_system)
    end
  end

  def handle_system_generation_subcommands([command | _subcommands], %RuleSystems.RuleSystem{} = system) do
    case command do
      :stat_block ->
        RuleSystems.RuleSystem.gen_ability_scores_assigned(system)
        |> IO.inspect()
    end
  end
end
