defmodule ExRPG.RuleSystems.RuleSystem do
  alias ExRPG.RuleSystems.Metadata

  @moduledoc """
  Module for handling a specific Rule System
  """

  defstruct [:metadata]

  @doc """
  Loads a RuleSystem struct from a json string representation

  ## Examples
      iex> ExRPG.RuleSystems.RuleSystem.from_json!("a json string")
      %ExRPG.RuleSystems.RuleSystem{}
  """
  def from_json!(system_config_json) when is_bitstring(system_config_json) do
    system_config_json
    |> Poison.decode!(as: %ExRPG.RuleSystems.RuleSystem{metadata: %Metadata{}})
  end
end
