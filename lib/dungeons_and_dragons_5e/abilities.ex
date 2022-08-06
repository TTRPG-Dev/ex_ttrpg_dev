defmodule ExRPG.DungoneAndDragons5e.Abilities do
  alias ExRPG.Dice
  @moduledoc """
  Specifications for D&D 5e character ability scores
  """

  @abilities %{
    :strength => :STR,
    :dexterity => :DEX,
    :constitution => :CON,
    :intellegence => :INT,
    :wisdom => :WIS,
    :charisma => :CHA
  }

  @rolling_method "3d6"

  @doc """
  Generates ability scores, assigned to abilities

  ## Examples
      iex> ExRPG.DungeonsAndDragons5e.Abilities.gen_scores
      %{
        charisma: [4, 3, 1],
        constitution: [5, 6, 3],
        dexterity: [5, 3, 1],
        intellegence: [4, 3, 3],
        strength: [4, 1, 5],
        wisdom: [1, 5, 6]
      }

  """
  def gen_scores do
    gen_scores_unassigned()
    |> Enum.zip(Map.keys(@abilities))
    |> Enum.reduce(%{}, fn {score, ability}, acc -> Map.put(acc, ability, score) end)
  end

  @doc """
  Generates scores to be assigned to abilities

  ## Examples
      iex> ExRPG.DungeonsAndDragons5e.Abilities.gen_scores_unassigned
      [[1, 6, 6], [3, 3, 2], [3, 6, 3], [4, 2, 1], [6, 5, 1], [6, 4, 6]]


  """
  def gen_scores_unassigned do
    Map.keys(@abilities)
    |> Enum.reduce([], fn _ability, acc -> [Dice.roll(@rolling_method) | acc] end)
  end
end
