defmodule ExTTRPGDev.Characters.Rolls do
  @moduledoc """
  Concept rolls: rolling the dice a system's roll definitions attach to a
  concept type, with the bonus resolved from the character's state.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.concept_roll!/4`); this module hosts the
  implementation.
  """

  alias DiceLib.Basic, as: Dice
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Effects
  alias ExTTRPGDev.RuleSystem.Vocabulary
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  # Bound to an attribute for use in pattern-match positions; the name is
  # owned by ExTTRPGDev.RuleSystem.Vocabulary.
  @roll_type Vocabulary.roll_type()

  @doc """
  Rolls for a concept using the roll definition attached to its type in the system config.

  See `ExTTRPGDev.Characters.concept_roll!/4` for documentation.
  """
  def concept_roll!(%LoadedSystem{} = system, %Character{} = character, type_id, concept_id) do
    roll_def =
      system.concept_metadata
      |> Enum.find(fn {{type, _id}, meta} ->
        type == @roll_type and meta["target_type"] == type_id
      end)

    unless roll_def do
      raise "No roll defined for concept type \"#{type_id}\" in system \"#{system.module.slug}\""
    end

    {_key, %{"dice" => dice_str, "bonus_field" => bonus_field}} = roll_def

    {_effects, resolved} = Effects.resolved_state(system, character)

    bonus_key = {type_id, concept_id, bonus_field}

    unless Map.has_key?(resolved, bonus_key) do
      raise "Concept \"#{type_id}('#{concept_id}')\" not found in system \"#{system.module.slug}\""
    end

    bonus = resolved[bonus_key]
    rolls = Dice.roll(dice_str)

    %{
      type_id: type_id,
      concept_id: concept_id,
      dice: dice_str,
      rolls: rolls,
      bonus: bonus,
      total: Enum.sum(rolls) + bonus
    }
  end
end
