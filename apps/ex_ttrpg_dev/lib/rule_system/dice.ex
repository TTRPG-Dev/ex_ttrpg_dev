defmodule ExTTRPGDev.RuleSystem.Dice do
  @moduledoc """
  A dice value: a pool of dice terms, whose summed roll is multiplied by
  `multiplier` and then offset by `modifier`.

      total = sum(rolls) * multiplier + modifier

  `terms` is a list of `{count, sides}` pairs: `2d6 + 1d8` is
  `[{2, 6}, {1, 8}]`. Terms are kept merged (one per die size) and ordered
  by size, so equal pools are equal structs.

  Dice values are what formula nodes produce with `dice(count, sides)` (see
  `ExTTRPGDev.RuleSystem.Expression`), and what mapping steps produce from
  dice notation. They are written in standard notation: the terms joined
  by `+`, then `*multiplier` when it isn't 1 (with the terms in parentheses
  if there is more than one), then a signed `modifier` when it isn't 0.

      iex> alias ExTTRPGDev.RuleSystem.Dice
      iex> to_string(%Dice{terms: [{2, 6}], modifier: 3})
      "2d6+3"
      iex> to_string(%Dice{terms: [{2, 6}, {1, 8}], modifier: 3})
      "2d6+1d8+3"
      iex> to_string(%Dice{terms: [{5, 4}], multiplier: 10})
      "5d4*10"
      iex> to_string(%Dice{terms: [{1, 4}, {1, 6}], multiplier: 10})
      "(1d4+1d6)*10"

  The same notation is accepted by `parse/1`, so a static dice string
  (`"1d8"`) and a computed dice value are interchangeable wherever a roll
  takes dice. Dice values encode to JSON as their notation string.

  ## Arithmetic

  The algebra is closed over what the notation can express:

    * `dice + n`, `n + dice`, `dice - n` — offset the modifier
    * `dice + dice` — pool the dice, of any sizes (`1d6 + 2d6` is `3d6`;
      `2d6 + 1d8` is `2d6+1d8`), when both have the same `multiplier`
    * `dice * n`, `n * dice` — scale the rolled total, for a positive
      integer `n` (the modifier scales with it, so `(1d4+1) * 10` is
      `1d4*10+10`)

  Every `n` must be an integer. Anything else is an error.
  """

  alias DiceLib.Basic

  @enforce_keys [:terms]
  defstruct [:terms, modifier: 0, multiplier: 1]

  @type term_pair :: {non_neg_integer(), pos_integer()}

  @type t :: %__MODULE__{
          terms: [term_pair(), ...],
          modifier: integer(),
          multiplier: pos_integer()
        }

  @term_notation ~r/\A(\d*)d(\d+)\z/
  @modifier_notation ~r/\A(.+?)([+-]\d+)\z/
  @grouped_multiplier_notation ~r/\A\((.+)\)\*(\d+)\z/
  @multiplier_notation ~r/\A([^()]+)\*(\d+)\z/

  @doc """
  Builds a dice value of `count` dice with `sides` sides.

  `count` may be zero (a formula like `dice(class_level, 6)` resolves for
  characters without the class too); `sides` must be at least 1.

  ## Examples

      iex> ExTTRPGDev.RuleSystem.Dice.new(3, 6)
      {:ok, %ExTTRPGDev.RuleSystem.Dice{terms: [{3, 6}]}}

      iex> ExTTRPGDev.RuleSystem.Dice.new(2.5, 6)
      {:error, "dice count must be a non-negative integer, got: 2.5"}

  """
  @spec new(term(), term()) :: {:ok, t()} | {:error, String.t()}
  def new(count, sides)
      when is_integer(count) and count >= 0 and is_integer(sides) and sides >= 1,
      do: {:ok, %__MODULE__{terms: [{count, sides}]}}

  def new(count, _sides) when not (is_integer(count) and count >= 0),
    do: {:error, "dice count must be a non-negative integer, got: #{inspect(count)}"}

  def new(_count, sides),
    do: {:error, "dice sides must be a positive integer, got: #{inspect(sides)}"}

  @doc """
  Parses dice notation into a dice value. A `%Dice{}` is returned as-is, so
  callers can accept either form.

  A term's count may be omitted (`"d8"` is `"1d8"`). Terms of the same size
  are merged (`"1d6+1d6"` is `"2d6"`).

  ## Examples

      iex> ExTTRPGDev.RuleSystem.Dice.parse("2d6+3")
      {:ok, %ExTTRPGDev.RuleSystem.Dice{terms: [{2, 6}], modifier: 3}}

      iex> ExTTRPGDev.RuleSystem.Dice.parse("1d8+2d6-1")
      {:ok, %ExTTRPGDev.RuleSystem.Dice{terms: [{2, 6}, {1, 8}], modifier: -1}}

      iex> ExTTRPGDev.RuleSystem.Dice.parse("d8")
      {:ok, %ExTTRPGDev.RuleSystem.Dice{terms: [{1, 8}]}}

      iex> ExTTRPGDev.RuleSystem.Dice.parse("5d4*10")
      {:ok, %ExTTRPGDev.RuleSystem.Dice{terms: [{5, 4}], multiplier: 10}}

      iex> ExTTRPGDev.RuleSystem.Dice.parse("2d")
      {:error, "invalid dice notation: \\"2d\\""}

  """
  @spec parse(t() | String.t()) :: {:ok, t()} | {:error, String.t()}
  def parse(%__MODULE__{} = dice), do: {:ok, dice}

  def parse(notation) when is_binary(notation) do
    {body, modifier} = split_modifier(String.trim(notation))

    with {:ok, pool, multiplier} <- split_multiplier(body),
         {:ok, dice} <- parse_pool(pool),
         {:ok, dice} <- apply_multiplier(dice, multiplier) do
      {:ok, %{dice | modifier: modifier}}
    else
      _ -> {:error, "invalid dice notation: #{inspect(notation)}"}
    end
  end

  def parse(other), do: {:error, "invalid dice notation: #{inspect(other)}"}

  # A trailing signed number is the modifier: "+1d8" can't match because
  # the term's "d" stops [+-]\d+ from reaching the end.
  defp split_modifier(notation) do
    case Regex.run(@modifier_notation, notation, capture: :all_but_first) do
      [body, modifier] -> {body, String.to_integer(modifier)}
      nil -> {notation, 0}
    end
  end

  # A multiplier applies to the whole pool: "(1d4+1d6)*10", or "5d4*10"
  # for a single term. "1d4+1d6*10" is rejected rather than guessed at.
  defp split_multiplier(body) do
    cond do
      match = Regex.run(@grouped_multiplier_notation, body, capture: :all_but_first) ->
        [pool, multiplier] = match
        {:ok, pool, String.to_integer(multiplier)}

      match = Regex.run(@multiplier_notation, body, capture: :all_but_first) ->
        [pool, multiplier] = match

        if String.contains?(pool, "+"),
          do: :error,
          else: {:ok, pool, String.to_integer(multiplier)}

      true ->
        {:ok, body, 1}
    end
  end

  defp parse_pool(pool) do
    pool
    |> String.split("+")
    |> Enum.reduce_while(:empty, fn term, acc ->
      with {:ok, dice} <- parse_term(term),
           {:ok, acc} <- pool_with(acc, dice) do
        {:cont, acc}
      else
        _ -> {:halt, :error}
      end
    end)
    |> case do
      %__MODULE__{} = dice -> {:ok, dice}
      _ -> :error
    end
  end

  defp parse_term(term) do
    case Regex.run(@term_notation, term, capture: :all_but_first) do
      [count, sides] -> new(parse_count(count), String.to_integer(sides))
      nil -> :error
    end
  end

  defp pool_with(:empty, dice), do: {:ok, dice}
  defp pool_with(acc, dice), do: add(acc, dice)

  defp parse_count(""), do: 1
  defp parse_count(count), do: String.to_integer(count)

  defp apply_multiplier(dice, 1), do: {:ok, dice}
  defp apply_multiplier(dice, multiplier), do: multiply(dice, multiplier)

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
      iex> Dice.add(%Dice{terms: [{1, 6}]}, %Dice{terms: [{2, 6}], modifier: 1})
      {:ok, %Dice{terms: [{3, 6}], modifier: 1}}
      iex> Dice.add(%Dice{terms: [{2, 6}]}, %Dice{terms: [{1, 8}]})
      {:ok, %Dice{terms: [{2, 6}, {1, 8}]}}
      iex> Dice.add(%Dice{terms: [{1, 6}]}, 2)
      {:ok, %Dice{terms: [{1, 6}], modifier: 2}}
      iex> Dice.add(%Dice{terms: [{1, 6}], multiplier: 10}, %Dice{terms: [{1, 6}]})
      {:error, "cannot add 1d6*10 and 1d6: dice must have the same multiplier"}

  """
  @spec add(t() | integer(), t() | integer()) :: {:ok, t()} | {:error, String.t()}
  def add(%__MODULE__{} = dice, n) when is_integer(n),
    do: {:ok, %{dice | modifier: dice.modifier + n}}

  def add(n, %__MODULE__{} = dice) when is_integer(n), do: add(dice, n)

  def add(%__MODULE__{multiplier: multiplier} = a, %__MODULE__{multiplier: multiplier} = b),
    do: {:ok, %{a | terms: merge_terms(a.terms ++ b.terms), modifier: a.modifier + b.modifier}}

  def add(%__MODULE__{} = a, %__MODULE__{} = b),
    do: {:error, "cannot add #{a} and #{b}: dice must have the same multiplier"}

  def add(a, b), do: {:error, "cannot add #{describe(a)} and #{describe(b)}"}

  # One term per die size, ordered by size. Zero-count terms (dice(0, 6)
  # for a character without the class) drop out once there's anything
  # else in the pool, so 0d6 + 1d8 is 1d8, but a pool of only zero-count
  # terms keeps them so it still prints as e.g. "0d6".
  defp merge_terms(terms) do
    merged =
      terms
      |> Enum.group_by(fn {_count, sides} -> sides end, fn {count, _sides} -> count end)
      |> Enum.map(fn {sides, counts} -> {Enum.sum(counts), sides} end)
      |> Enum.sort_by(fn {_count, sides} -> sides end)

    case Enum.reject(merged, fn {count, _sides} -> count == 0 end) do
      [] -> merged
      nonzero -> nonzero
    end
  end

  @doc """
  Multiplies a dice value's rolled total by a positive integer.

  ## Examples

      iex> alias ExTTRPGDev.RuleSystem.Dice
      iex> Dice.multiply(%Dice{terms: [{1, 4}], modifier: 1}, 10)
      {:ok, %Dice{terms: [{1, 4}], multiplier: 10, modifier: 10}}
      iex> Dice.multiply(%Dice{terms: [{1, 4}]}, %Dice{terms: [{1, 4}]})
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
  Rolls a dice value (or dice notation).

  Returns the individual die results (`:rolls`, every term's dice in term
  order), the same results grouped by term (`:rolls_by_term`, each with its
  term's notation), and the total after the multiplier and modifier.

  Raises `ArgumentError` on invalid notation.

  ## Examples

      iex> :rand.seed(:exsplus, 1337)
      iex> ExTTRPGDev.RuleSystem.Dice.roll("3d8+2")
      %{rolls: [4, 8, 5], rolls_by_term: [%{dice: "3d8", rolls: [4, 8, 5]}], total: 19}

      iex> ExTTRPGDev.RuleSystem.Dice.roll(%ExTTRPGDev.RuleSystem.Dice{terms: [{0, 6}], modifier: 1})
      %{rolls: [], rolls_by_term: [%{dice: "0d6", rolls: []}], total: 1}

  """
  @spec roll(t() | String.t()) :: %{
          rolls: [pos_integer()],
          rolls_by_term: [%{dice: String.t(), rolls: [pos_integer()]}],
          total: integer()
        }
  def roll(dice) do
    %__MODULE__{terms: terms, multiplier: multiplier, modifier: modifier} = parse!(dice)

    rolls_by_term =
      Enum.map(terms, fn {count, sides} ->
        %{dice: "#{count}d#{sides}", rolls: roll_term(count, sides)}
      end)

    rolls = Enum.flat_map(rolls_by_term, & &1.rolls)
    %{rolls: rolls, rolls_by_term: rolls_by_term, total: Enum.sum(rolls) * multiplier + modifier}
  end

  # DiceLib maps over 1..count, which for a count of 0 is a descending
  # range of two elements rather than an empty one.
  defp roll_term(0, _sides), do: []
  defp roll_term(count, sides), do: Basic.roll(count, sides)

  defimpl String.Chars do
    def to_string(%{terms: terms, multiplier: multiplier, modifier: modifier}) do
      pool = Enum.map_join(terms, "+", fn {count, sides} -> "#{count}d#{sides}" end)
      multiplied(pool, length(terms), multiplier) <> modifier_suffix(modifier)
    end

    defp multiplied(pool, _term_count, 1), do: pool
    defp multiplied(pool, 1, multiplier), do: "#{pool}*#{multiplier}"
    defp multiplied(pool, _term_count, multiplier), do: "(#{pool})*#{multiplier}"

    defp modifier_suffix(0), do: ""
    defp modifier_suffix(modifier) when modifier > 0, do: "+#{modifier}"
    defp modifier_suffix(modifier), do: "#{modifier}"
  end

  defimpl Jason.Encoder do
    def encode(dice, opts), do: Jason.Encode.string(to_string(dice), opts)
  end
end
