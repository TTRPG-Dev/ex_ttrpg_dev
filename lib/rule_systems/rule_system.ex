defmodule ExRPG.RuleSystems.RuleSystem do
  alias ExRPG.RuleSystems.Metadata
  alias ExRPG.RuleSystems.Abilities

  @moduledoc """
  Module for handling a specific Rule System
  """

  defstruct [:metadata, :abilities]

  @doc """
  Loads a RuleSystem struct from a json string representation

  ## Examples
      iex> ExRPG.RuleSystems.RuleSystem.from_json!("a json string")
      %ExRPG.RuleSystems.RuleSystem{}
  """
  def from_json!(system_config_json) when is_bitstring(system_config_json) do
    system_config_json
    |> Poison.decode!(as: %ExRPG.RuleSystems.RuleSystem{
      metadata: %Metadata{},
      abilities: %Abilities{
        assignment: %Abilities.Assignment{
          rolling_methods: [%Abilities.Assignment.RollingMethod{}],
          point_buy: %Abilities.Assignment.PointBuy{
            score_costs: [%Abilities.Assignment.PointBuy.ScoreCost{}]
          }
        },
        modifier_calculation: %Abilities.ModifierCalculation{
          steps: [%Abilities.ModifierCalculation.Step{}],
          mapping: [%Abilities.ModifierCalculation.Mapping{}]
        },
        specs: [%Abilities.Spec{}]
      }
    })
  end
end
