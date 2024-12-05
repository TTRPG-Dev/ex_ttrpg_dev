defmodule ExTTRPGDev.Characters.Character do
  alias __MODULE__
  alias ExTTRPGDev.Characters.Metadata
  alias ExTTRPGDev.RuleSystems

  @moduledoc """
  Definition of an individual character
  """
  defstruct [:name, :ability_scores, :metadata]

  @doc """
  Load a character from json representation
  """
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

  @doc """
  Returns an auto generated character for the system

  ## Examples
    iex> Character.gen_character(rule_system)
    %Character{}
  """
  def gen_character!(%RuleSystems.RuleSystem{
        abilities: %RuleSystems.Abilities{} = abilities,
        metadata: %RuleSystems.Metadata{} = rule_system_metadata
      }) do
    character_name = Faker.Person.name()

    %Character{
      name: character_name,
      ability_scores: RuleSystems.Abilities.gen_scores(abilities),
      metadata: %ExTTRPGDev.Characters.Metadata{
        slug:
          character_name
          |> String.downcase()
          |> String.replace(~r/[!#$%&()*+,.:;<=>?@\^_`'{|}~-]/, "")
          |> String.replace(" ", "_"),
        rule_system: rule_system_metadata
      }
    }
  end
end
