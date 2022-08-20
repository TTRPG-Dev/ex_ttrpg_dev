defmodule ExRPG.Dice do
  @moduledoc """
  This module deals with the rolling of any and all dice
  """

  @dice_regex ~r/^([0-9]+)d([0-9]+)$/

  @doc """
  Validates that a given string conforms to the expexted dice specifying format

  Returns: the input string

  ## Examples

      iex> ExRPG.Dice.validate_dice_str("3d4")
      "3d4"

  """
  def validate_dice_str(str) do
    if not Regex.match?(@dice_regex, str) do
      raise "Improper dice format. Dice must be given in xdy where x and y are both integers"
    end

    str
  end

  @doc """
  Rolls the a number of multisided dice

  Returns: List of die roll results

  ## Examples

      iex> ExRPG.Dice.roll(3, 4)
      [1, 4, 2]

  """
  def roll(number_of_dice, dice_sides) do
    Enum.map(1..number_of_dice, fn _ -> roll(dice_sides) end)
  end

  @doc """
  Roll dice defined by the input string

  Returns: List of die roll results

  ## Examples

      iex> ExRPG.Dice.roll("3d4")
      [1, 4, 2]

  """
  def roll(str) when is_bitstring(str) do
    [number_of_dice, sides] =
      str
      |> validate_dice_str()
      |> String.split("d")
      |> Enum.map(fn x -> String.to_integer(x) end)

    roll(number_of_dice, sides)
  end

  @doc """
  Rolls a die with the number of sides given in the input

  Returns: the rolled number

  ## Examples

      iex> ExRPG.Dice.roll(4)
      3

  """
  def roll(sides) when is_integer(sides) do
    :rand.uniform(sides)
  end
end
