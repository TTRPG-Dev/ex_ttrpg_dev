defmodule ExTTRPGDev.RuleSystem.Dice do
  @moduledoc """
  A dice value: `count` dice of `sides` sides, whose summed roll is
  multiplied by `multiplier` and then offset by `modifier`.

      total = sum(rolls) * multiplier + modifier

  Dice values are what formula nodes produce with `dice(count, sides)` (see
  `ExTTRPGDev.RuleSystem.Expression`), and what mapping steps produce from
  dice notation. They are written in standard notation — `count`, `d`,
  `sides`, then `*multiplier` when it isn't 1 and a signed `modifier` when
  it isn't 0:

      iex> alias ExTTRPGDev.RuleSystem.Dice
      iex> to_string(%Dice{count: 2, sides: 6, modifier: 3})
      "2d6+3"
      iex> to_string(%Dice{count: 5, sides: 4, multiplier: 10})
      "5d4*10"

  The same notation is accepted by `parse/1`, so a static dice string
  (`"1d8"`) and a computed dice value are interchangeable wherever a roll
  takes dice. Dice values encode to JSON as their notation string.

  ## Arithmetic

  The algebra is closed over what the notation can express:

    * `dice + n`, `n + dice`, `dice - n` — offset the modifier
    * `dice + dice` — sum the dice, when both have the same `sides` and
      `multiplier` (`1d6 + 2d6` is `3d6`; `1d6 + 1d8` is an error)
    * `dice * n`, `n * dice` — scale the rolled total, for a positive
      integer `n` (the modifier scales with it, so `(1d4+1) * 10` is
      `1d4*10+10`)

  Every `n` must be an integer. Anything else is an error.
  """

  alias DiceLib.Basic

  @enforce_keys [:count, :sides]
  defstruct [:count, :sides, modifier: 0, multiplier: 1]

  @type t :: %__MODULE__{
          count: non_neg_integer(),
          sides: pos_integer(),
          modifier: integer(),
          multiplier: pos_integer()
        }

  @notation ~r/\A(\d*)d(\d+)(?:\*(\d+))?([+-]\d+)?\z/

  @doc """
  Builds a dice value of `count` dice with `sides` sides.

  `count` may be zero (a formula like `dice(class_level, 6)` resolves for
  characters without the class too); `sides` must be at least 1.

  ## Examples

      iex> ExTTRPGDev.RuleSystem.Dice.new(3, 6)
      {:ok, %ExTTRPGDev.RuleSystem.Dice{count: 3, sides: 6}}

      iex> ExTTRPGDev.RuleSystem.Dice.new(2.5, 6)
      {:error, "dice count must be a non-negative integer, got: 2.5"}

  """
  @spec new(term(), term()) :: {:ok, t()} | {:error, String.t()}
  def new(count, sides)
      when is_integer(count) and count >= 0 and is_integer(sides) and sides >= 1,
      do: {:ok, %__MODULE__{count: count, sides: sides}}

  def new(count, _sides) when not (is_integer(count) and count >= 0),
    do: {:error, "dice count must be a non-negative integer, got: #{inspect(count)}"}

  def new(_count, sides),
    do: {:error, "dice sides must be a positive integer, got: #{inspect(sides)}"}

  @doc """
  Parses dice notation into a dice value. A `%Dice{}` is returned as-is, so
  callers can accept either form.

  The count may be omitted (`"d8"` is `"1d8"`).

  ## Examples

      iex> ExTTRPGDev.RuleSystem.Dice.parse("2d6+3")
      {:ok, %ExTTRPGDev.RuleSystem.Dice{count: 2, sides: 6, modifier: 3}}

      iex> ExTTRPGDev.RuleSystem.Dice.parse("d8")
      {:ok, %ExTTRPGDev.RuleSystem.Dice{count: 1, sides: 8}}

      iex> ExTTRPGDev.RuleSystem.Dice.parse("5d4*10")
      {:ok, %ExTTRPGDev.RuleSystem.Dice{count: 5, sides: 4, multiplier: 10}}

      iex> ExTTRPGDev.RuleSystem.Dice.parse("2d")
      {:error, "invalid dice notation: \\"2d\\""}

  """
  @spec parse(t() | String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(%__MODULE__{} = dice), do: {:ok, dice}

  def parse(notation) when is_binary(notation) do
    with [count, sides | rest] <-
           Regex.run(@notation, String.trim(notation), capture: :all_but_first),
         {:ok, dice} <- new(parse_count(count), String.to_integer(sides)),
         {:ok, dice} <- apply_multiplier(dice, Enum.at(rest, 0, "")) do
      {:ok, %{dice | modifier: parse_modifier(Enum.at(rest, 1, ""))}}
    else
      _ -> {:error, "invalid dice notation: #{inspect(notation)}"}
    end
  end

  def parse(other), do: {:error, "invalid dice notation: #{inspect(other)}"}

  defp parse_count(""), do: 1
  defp parse_count(count), do: String.to_integer(count)

  defp apply_multiplier(dice, ""), do: {:ok, dice}
  defp apply_multiplier(dice, multiplier), do: multiply(dice, String.to_integer(multiplier))

  defp parse_modifier(""), do: 0
  defp parse_modifier(modifier), do: String.to_integer(modifier)

  @doc "Same as `parse/1` but raises `ArgumentError` on invalid notation."
  @spec parse!(t() | String.t()) :: t()
  def parse!(notation) do
    case parse(notation) do
      {:ok, dice} -> dice
      {:error, message} -> raise ArgumentError, message
    end
  end

  @doc """
  Adds two values, at least one of them dice. See the moduledoc for which
  combinations are defined.

  ## Examples

      iex> alias ExTTRPGDev.RuleSystem.Dice
      iex> Dice.add(%Dice{count: 1, sides: 6}, %Dice{count: 2, sides: 6, modifier: 1})
      {:ok, %Dice{count: 3, sides: 6, modifier: 1}}
      iex> Dice.add(%Dice{count: 1, sides: 6}, 2)
      {:ok, %Dice{count: 1, sides: 6, modifier: 2}}
      iex> Dice.add(%Dice{count: 1, sides: 6}, %Dice{count: 1, sides: 8})
      {:error, "cannot add 1d6 and 1d8: dice must have the same sides and multiplier"}

  """
  @spec add(t() | integer(), t() | integer()) :: {:ok, t()} | {:error, String.t()}
  def add(%__MODULE__{} = dice, n) when is_integer(n),
    do: {:ok, %{dice | modifier: dice.modifier + n}}

  def add(n, %__MODULE__{} = dice) when is_integer(n), do: add(dice, n)

  def add(
        %__MODULE__{sides: sides, multiplier: multiplier} = a,
        %__MODULE__{sides: sides, multiplier: multiplier} = b
      ),
      do: {:ok, %{a | count: a.count + b.count, modifier: a.modifier + b.modifier}}

  def add(%__MODULE__{} = a, %__MODULE__{} = b),
    do: {:error, "cannot add #{a} and #{b}: dice must have the same sides and multiplier"}

  def add(a, b), do: {:error, "cannot add #{describe(a)} and #{describe(b)}"}

  @doc """
  Multiplies a dice value's rolled total by a positive integer.

  ## Examples

      iex> alias ExTTRPGDev.RuleSystem.Dice
      iex> Dice.multiply(%Dice{count: 1, sides: 4, modifier: 1}, 10)
      {:ok, %Dice{count: 1, sides: 4, multiplier: 10, modifier: 10}}
      iex> Dice.multiply(%Dice{count: 1, sides: 4}, %Dice{count: 1, sides: 4})
      {:error, "cannot multiply 1d4 by 1d4: dice can only be multiplied by a positive integer"}

  """
  @spec multiply(t() | integer(), t() | integer()) :: {:ok, t()} | {:error, String.t()}
  def multiply(%__MODULE__{} = dice, n) when is_integer(n) and n >= 1,
    do: {:ok, %{dice | multiplier: dice.multiplier * n, modifier: dice.modifier * n}}

  def multiply(n, %__MODULE__{} = dice) when is_integer(n) and n >= 1, do: multiply(dice, n)

  def multiply(a, b) do
    {:error,
     "cannot multiply #{describe(a)} by #{describe(b)}: " <>
       "dice can only be multiplied by a positive integer"}
  end

  defp describe(%__MODULE__{} = dice), do: to_string(dice)
  defp describe(other), do: inspect(other)

  @doc """
  Rolls a dice value (or dice notation), returning the individual die
  results and the total after the multiplier and modifier.

  Raises `ArgumentError` on invalid notation.

  ## Examples

      iex> :rand.seed(:exsplus, 1337)
      iex> ExTTRPGDev.RuleSystem.Dice.roll("3d8+2")
      %{rolls: [4, 8, 5], total: 19}

      iex> ExTTRPGDev.RuleSystem.Dice.roll(%ExTTRPGDev.RuleSystem.Dice{count: 0, sides: 6, modifier: 1})
      %{rolls: [], total: 1}

  """
  @spec roll(t() | String.t()) :: %{rolls: [pos_integer()], total: integer()}
  def roll(dice) do
    %__MODULE__{count: count, sides: sides, multiplier: multiplier, modifier: modifier} =
      parse!(dice)

    # DiceLib maps over 1..count, which for a count of 0 is a descending
    # range of two elements rather than an empty one.
    rolls = if count == 0, do: [], else: Basic.roll(count, sides)
    %{rolls: rolls, total: Enum.sum(rolls) * multiplier + modifier}
  end

  defimpl String.Chars do
    def to_string(%{count: count, sides: sides, multiplier: multiplier, modifier: modifier}) do
      "#{count}d#{sides}" <> multiplier_suffix(multiplier) <> modifier_suffix(modifier)
    end

    defp multiplier_suffix(1), do: ""
    defp multiplier_suffix(multiplier), do: "*#{multiplier}"

    defp modifier_suffix(0), do: ""
    defp modifier_suffix(modifier) when modifier > 0, do: "+#{modifier}"
    defp modifier_suffix(modifier), do: "#{modifier}"
  end

  defimpl Jason.Encoder do
    def encode(dice, opts), do: Jason.Encode.string(to_string(dice), opts)
  end
end
