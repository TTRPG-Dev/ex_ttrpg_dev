defmodule ExTTRPGDev.RuleSystems.RuleSystem do
  alias ExTTRPGDev.RuleSystems.RuleSystem
  alias ExTTRPGDev.RuleSystems.Metadata
  alias ExTTRPGDev.RuleSystems.Abilities
  alias ExTTRPGDev.RuleSystems.Skills
  alias ExTTRPGDev.RuleSystems.Languages
  alias ExTTRPGDev.RuleSystems.Characters

  @moduledoc """
  Module for handling a specific Rule System
  """

  defstruct [:metadata, :abilities, :skills, :languages]

  @doc """
  Loads a RuleSystem struct from a json string representation

  ## Examples
      iex> ExTTRPGDev.RuleSystems.RuleSystem.from_json!("a json string")
      %ExTTRPGDev.RuleSystems.RuleSystem{}
  """
  def from_json!(system_config_json) when is_bitstring(system_config_json) do
    system_config_json
    |> Poison.decode!(
      as: %ExTTRPGDev.RuleSystems.RuleSystem{
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
        },
        skills: [%Skills.Skill{}],
        languages: [%Languages.Language{}]
      }
    )
  end

  @doc """
  Generates a set of ability scores assigned to the rule systems abilities
  using the system's default assignment method .

  ## Examples

      iex> RuleSystem.gen_ability_scores()
      %{
        charisma: [4, 3, 1],
        constitution: [5, 6, 3],
        dexterity: [5, 3, 1],
        intellegence: [4, 3, 3],
        strength: [4, 1, 5],
        wisdom: [1, 5, 6]
      }
  """
  def gen_ability_scores_assigned(%RuleSystem{abilities: %Abilities{} = abilities}) do
    Abilities.gen_scores(abilities)
  end

  @doc """
  Generates an unassigned set of ability scores using the system's default
  assignment method.

  ## Examples

      iex> RuleSystem.gen_ability_scores(%RuleSystem{})
      [[1, 6, 6], [3, 3, 2], [3, 6, 3], [4, 2, 1], [6, 5, 1], [6, 4, 6]]

  """
  def gen_ability_scores_unassigned(%RuleSystem{abilities: %Abilities{} = abilities}) do
    Abilities.gen_scores_unassigned(abilities)
  end

  @doc """
  Returns the spec for the given spec name

  ## Examples

      iex> ExTTRPGDev.RuleSystems.get_spec_by_name(rule_system, spec_name)
      %Spec{}
  """
  def get_spec_by_name(%RuleSystem{abilities: abilities}, spec_name)
      when is_bitstring(spec_name) do
    Abilities.get_spec_by_name(abilities, spec_name)
  end

  @doc """
  Returns an auto generated character for the system

  ## Examples
    iex> ExTTRPGDev.RuleSystems.gen_character(rule_system)
    %Characters.Character{}
  """
  def gen_character!(%RuleSystem{
        abilities: %Abilities{} = abilities,
        metadata: %Metadata{} = metadata
      }) do
    %Characters.Character{
      name: Faker.Person.name(),
      ability_scores: Abilities.gen_scores(abilities),
      rule_system: metadata
    }
  end
end
