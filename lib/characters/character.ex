defmodule ExTTRPGDev.Characters.Character do
  alias __MODULE__
  alias ExTTRPGDev.Characters.Metadata
  alias ExTTRPGDev.RuleSystems

  @moduledoc """
  Definition of an individual character
  """
  defstruct [:name, :ability_scores, :metadata]

  def from_json!(character_json) when is_bitstring(character_json) do
    character_json
    |> Poison.decode!(
      as: %Character{
        metadata: %Metadata{
          rule_system: %RuleSystems.Metadata{}
        }
      }
    )
  end
end
