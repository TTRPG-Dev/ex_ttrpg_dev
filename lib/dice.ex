defmodule ExTTRPGDev.Dice do
  @moduledoc """
  This module deals with the rolling of any and all dice
  """

  @dice_regex ~r/^([0-9]+)d([0-9]+)$/

  @doc """
  Validates that a given string conforms to the expexted dice specifying format

  Returns: the input string

  ## Examples

      iex> ExTTRPGDev.Dice.validate_dice_str("3d4")
      "3d4"

      iex> ExTTRPGDev.Dice.validate_dice_str("3")
      ** (RuntimeError) Improper dice format. Dice must be given in xdy where x and y are both integers

  """
  def validate_dice_str(str) do
    if not Regex.match?(@dice_regex, str) do
      raise "Improper dice format. Dice must be given in xdy where x and y are both integers"
    end

    str
  end

  @doc """
  Tries to parse a given dice spec string into it's component parts

  Returns: a tuple where the first item is the number of times to roll the die and the second indicates the  number or sides the die has

  ## Examples

      iex> ExTTRPGDev.Dice.parse_roll_spec!("3d4")
      {3, 4}

      iex> ExTTRPGDev.Dice.parse_roll_spec!("3")
      ** (RuntimeError) Improper dice format. Dice must be given in xdy where x and y are both integers

  """

  def parse_roll_spec!(roll_spec) when is_bitstring(roll_spec) do
    roll_spec
    |> validate_dice_str()
    |> String.split("d")
    |> Enum.map(fn x -> String.to_integer(x) end)
    |> List.to_tuple()
  end

  @doc """
  Rolls the a number of multisided dice

  Returns: List of die roll results

  ## Examples

      # Although not necessary, let's seed the random algorithm
      iex> :rand.seed(:exsplus, 1337)
      iex> ExTTRPGDev.Dice.roll(3, 8)
      [4, 8, 5]

  """
  def roll(number_of_dice, dice_sides) do
    Enum.map(1..number_of_dice, fn _ -> roll_d(dice_sides) end)
  end

  @doc """
  Roll dice defined by the input string

  Returns: List of die roll results

  ## Examples

      # Although not necessary, let's seed the random algorithm
      iex> :rand.seed(:exsplus, 1337)
      iex> ExTTRPGDev.Dice.roll("3d4")
      [4, 4, 1]

  """
  def roll(str) when is_bitstring(str) do
    {number_of_dice, sides} = parse_roll_spec!(str)
    roll(number_of_dice, sides)
  end

  @doc """
  Roll multiple roll specs

  Returns: List of tuples, the first value being the roll spec, the second being the results

  ## Examples
      # Although not necessary, let's seed the random algorithm
      iex> :rand.seed(:exsplus, 1337)
      iex> ExTTRPGDev.Dice.multi_roll!(["3d4", "4d8", "2d20"])
      [{"3d4", [4, 4, 1]}, {"4d8", [1, 3, 5, 6]}, {"2d20", [5, 12]}]

      iex> ExTTRPGDev.Dice.multi_roll!(["bad_spec", "oh_no!", "3d4"])
      ** (RuntimeError) Improper dice format. Dice must be given in xdy where x and y are both integers

  """
  def multi_roll!(roll_specs) when is_list(roll_specs) do
    roll_specs
    |> Enum.map(fn roll_spec -> {roll_spec, roll(roll_spec)} end)
  end

  @doc """
  Rolls a die with the number of sides given in the input

  Returns: the rolled number

  ## Examples

      # Although not necessary, let's seed the random algorithm
      iex> :rand.seed(:exsplus, 1337)
      iex> ExTTRPGDev.Dice.roll_d(6)
      6
      iex> ExTTRPGDev.Dice.roll_d(6)
      2

  """
  def roll_d(sides) when is_integer(sides) do
    :rand.uniform(sides)
  end
end
