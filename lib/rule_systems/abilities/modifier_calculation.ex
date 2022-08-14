defmodule ExRPG.RuleSystems.Abilities.ModifierCalculation do
  alias ExRPG.RuleSystems.Abilities.ModifierCalculation

  defstruct [:steps, :mapping]

  defmodule Step do
    defstruct [:order, :method, :value]
  end

  defmodule Mapping do
    defstruct [:ability_value, :modifier_value]
  end

  def modifier_for_score(%ModifierCalculation{steps: [%ModifierCalculation.Step{} | _tail] = steps, mapping: nil}, score) do
    steps
    |> ModifierCalculation.ordered_steps()
    |> Enum.reduce(score, fn step, acc -> ModifierCalculation.modify_score_by_step(step, acc) end)
  end

  def modifier_for_score(%ModifierCalculation{steps: nil, mapping: [%ModifierCalculation.Mapping{} | _tail] = mappings}, score) do
    mappings
    |> ModifierCalculation.map_mappings()
    |> Map.get(score)
  end

  def map_mappings([%ModifierCalculation.Mapping{} | _tail] = mappings) do
    mappings
    |> Enum.reduce(%{}, fn mapping, acc -> Map.put(acc, Map.get(mapping, :ability_value), Map.get(mapping, :modifier_value)) end)
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

  def ordered_steps([%ModifierCalculation.Step{} | _tail] = steps) do
    steps
    |> Enum.sort(fn a, b -> Map.get(a, :order) <= Map.get(b, :order) end)
  end

end