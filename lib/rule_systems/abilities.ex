defmodule ExRPG.RuleSystems.Abilities do
  alias ExRPG.RuleSystems.Abilities
  alias ExRPG.RuleSystems.Abilities.Spec
  alias ExRPG.RuleSystems.Abilities.Assignment

  @moduledoc """
  Root module for rule system ability tools
  """

  defstruct [:assignment, :modifier_calculation, :specs]

  @doc """
  Generates ability scores, assigned to abilities

  ## Examples
      iex> ExRPG.RuleSystems.Abilities.gen_scores(%ExRPG.RuleSystems.Abilities)
      %{
        charisma: [4, 3, 1],
        constitution: [5, 6, 3],
        dexterity: [5, 3, 1],
        intellegence: [4, 3, 3],
        strength: [4, 1, 5],
        wisdom: [1, 5, 6]
      }

  """
  def gen_scores(%Abilities{specs: [%Spec{} | _tail] = specs} = abilities) do
    spec_names = Spec.get_names(specs)

    gen_scores_unassigned(abilities)
    |> Enum.zip(spec_names)
    |> Enum.reduce(%{}, fn {score, ability}, acc -> Map.put(acc, ability, score) end)
  end

  @doc """
  Generates scores to be assigned to abilities

  ## Examples
      iex> ExRPG.RuleSystems.Abilities.gen_scores_unassigned(%Abilities{})
      [[1, 6, 6], [3, 3, 2], [3, 6, 3], [4, 2, 1], [6, 5, 1], [6, 4, 6]]


  """
  def gen_scores_unassigned(%Abilities{specs: [%Spec{} | _tail] = specs, assignment: %Assignment{} = assignment}) do
    default_rolling_method = Assignment.default_assignment(assignment)
    Enum.reduce(1..length(specs), [], fn _x, acc -> [Assignment.roll_via_method!(default_rolling_method) | acc] end)
  end
end
