defmodule ExRPG.RuleSystems.Abilities.ModifierCalculation do
  alias ExRPG.RuleSystems.Abilities.ModifierCalculation

  @moduledoc """
  Module handling calculation of ability modifiers based on ability scores
  """

  defstruct [:steps, :mapping]

  defmodule Step do
    @moduledoc """
    A step is generally part of a series of step which taken in order
    can calculate from the modifier from the starting ability score
    """
    defstruct [:order, :method, :value]
  end

  defmodule Mapping do
    @moduledoc """
    Defines direct mapping of ability scores to their modifer values
    """
    defstruct [:ability_value, :modifier_value]
  end

  @doc """
  Takes in a ModifierCalculation struct and a score, and calculates the scores modifier

  ## Examples

      iex> modifier_for_score(%ModifierCalculation{steps: [%Step{}, %Step{}, ...]}, 13)
      1
      modifier_for_score(%ModifierCalculation{mapping: [%Mapping{}, %Mapping, ...], 6)
      -2

  """
  def modifier_for_score(
        %ModifierCalculation{steps: [%ModifierCalculation.Step{} | _tail] = steps, mapping: nil},
        score
      ) do
    steps
    |> ordered_steps()
    |> Enum.reduce(score, fn step, acc -> ModifierCalculation.modify_score_by_step(step, acc) end)
  end

  def modifier_for_score(
        %ModifierCalculation{
          steps: nil,
          mapping: [%ModifierCalculation.Mapping{} | _tail] = mappings
        },
        score
      ) do
    mappings
    |> map_mappings()
    |> Map.get(score)
  end

  defp map_mappings([%ModifierCalculation.Mapping{} | _tail] = mappings) do
    mappings
    |> Enum.reduce(%{}, fn mapping, acc ->
      Map.put(acc, Map.get(mapping, :ability_value), Map.get(mapping, :modifier_value))
    end)
  end

  def modify_score_by_step(%ModifierCalculation.Step{} = step, score) do
    case step do
      %ModifierCalculation.Step{order: _, method: "add", value: value} ->
        score + value

      %ModifierCalculation.Step{order: _, method: "subtract", value: value} ->
        score - value

      %ModifierCalculation.Step{order: _, method: "multiply", value: value} ->
        score * value

      %ModifierCalculation.Step{order: _, method: "divide", value: value} ->
        score / value

      %ModifierCalculation.Step{order: _, method: "round_down", value: nil} ->
        Float.floor(score) |> Kernel.trunc()

      %ModifierCalculation.Step{order: _, method: "round_up", value: nil} ->
        Float.ceil(score) |> Kernel.trunc()
    end
  end

  defp ordered_steps([%ModifierCalculation.Step{} | _tail] = steps) do
    steps
    |> Enum.sort(fn a, b -> Map.get(a, :order) <= Map.get(b, :order) end)
  end
end
