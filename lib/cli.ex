defmodule ExRPG.CLI do
  alias ExRPG.Dice
  alias ExRPG.DungoneAndDragons5e
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
        gen: [
          name: "gen",
          about: "Used for generating things",
          subcommands: [
            stat_block: [
              name: "stat-block",
              about: "Generate stat blocks",
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

      default ->
        IO.inspect(default)
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
end
