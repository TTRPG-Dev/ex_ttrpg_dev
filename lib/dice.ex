defmodule ExRPG.Dice do

  @moduledoc """

  """

  @dice_regex ~r/^([0-9]+)d([0-9]+)$/

  def validate_dice_str(str) do
    if not Regex.match?(@dice_regex, str) do
      raise "Improper dice format. Dice must be given in xdy where x and y are both integers"
    end

    str
  end

  def roll(number_of_dice, dice_sides) do
    Enum.map(1..number_of_dice, fn _ -> roll(dice_sides) end)
  end

  def roll(str) when is_bitstring(str) do
    [number_of_dice, sides] = str
    |> validate_dice_str()
    |> String.split("d")
    |> Enum.map(fn x -> String.to_integer(x) end)

    roll(number_of_dice, sides)
  end

  def roll(sides) when is_integer(sides) do
    :rand.uniform(sides)
  end
end
