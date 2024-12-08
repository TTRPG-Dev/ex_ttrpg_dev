# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI.Roll do
  @moduledoc """
  Defintions for dealing with the CLI `roll` commond
  """
  alias ExTTRPGDev.Dice
  alias ExTTRPGDev.CustomParsers

  @doc """
  Command specifications for CLI `roll` command
  """
  def commands do
    [
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
      ]
    ]
  end

  @doc """
  Handles CLI `roll` command
  """
  def handle(%Optimus.ParseResult{args: %{dice: dice}}) do
    dice
    |> Dice.multi_roll!()
    |> Enum.each(fn {dice_spec, results} ->
      IO.inspect(results, label: dice_spec, charlists: :as_lists)
    end)
  end
end
