defmodule ExTTRPGDev.Characters.Rolls do
  @moduledoc """
  Concept rolls: rolling the dice a system's roll definitions attach to a
  concept type, with the bonus resolved from the character's state.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.concept_roll!/4`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Effects
  alias ExTTRPGDev.RuleSystem.Dice
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

    {{_roll_type, roll_id}, roll_meta} = roll_def

    unless Map.has_key?(system.concept_metadata, {type_id, concept_id}) do
      raise "Concept \"#{type_id}('#{concept_id}')\" not found in system \"#{system.module.slug}\""
    end

    {_effects, resolved} = Effects.resolved_state(system, character)
    node = &fetch_node!(resolved, {type_id, concept_id, &1}, roll_id)

    dice = roll_dice!(roll_meta, roll_id, node)
    bonus = roll_bonus!(roll_meta, roll_id, node)
    %{rolls: rolls, total: total} = Dice.roll(dice)

    %{
      type_id: type_id,
      concept_id: concept_id,
      dice: to_string(dice),
      rolls: rolls,
      bonus: bonus,
      total: total + bonus
    }
  end

  # A roll definition takes its dice either from fixed `dice` notation or
  # from `dice_field`, a node on the target concept whose resolved value is
  # dice (from `dice()` or a dice-valued mapping) or dice notation.
  defp roll_dice!(%{"dice" => _, "dice_field" => _}, roll_id, _node) do
    raise "Roll #{inspect(roll_id)} declares both \"dice\" and \"dice_field\"; use one"
  end

  defp roll_dice!(%{"dice_field" => field}, roll_id, node) do
    case Dice.parse(node.(field)) do
      {:ok, dice} ->
        dice

      {:error, _} ->
        raise "Roll #{inspect(roll_id)} reads dice from field #{inspect(field)}, " <>
                "which resolved to #{inspect(node.(field))} rather than dice"
    end
  end

  defp roll_dice!(%{"dice" => notation}, roll_id, _node) do
    case Dice.parse(notation) do
      {:ok, dice} -> dice
      {:error, message} -> raise "Roll #{inspect(roll_id)} has #{message}"
    end
  end

  defp roll_dice!(_roll_meta, roll_id, _node) do
    raise "Roll #{inspect(roll_id)} declares neither \"dice\" nor \"dice_field\""
  end

  # `bonus_field` is optional: a damage pool such as Sneak Attack has no
  # bonus beyond what its dice already carry.
  defp roll_bonus!(%{"bonus_field" => field}, roll_id, node) do
    case node.(field) do
      bonus when is_number(bonus) ->
        bonus

      other ->
        raise "Roll #{inspect(roll_id)} reads its bonus from field #{inspect(field)}, " <>
                "which resolved to #{inspect(other)} rather than a number"
    end
  end

  defp roll_bonus!(_roll_meta, _roll_id, _node), do: 0

  defp fetch_node!(resolved, {type_id, concept_id, field} = key, roll_id) do
    case Map.fetch(resolved, key) do
      {:ok, value} ->
        value

      :error ->
        raise "Roll #{inspect(roll_id)} reads field #{inspect(field)}, " <>
                "which concept \"#{type_id}('#{concept_id}')\" does not have"
    end
  end
end
