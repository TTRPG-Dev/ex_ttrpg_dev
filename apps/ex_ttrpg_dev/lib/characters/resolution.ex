defmodule ExTTRPGDev.Characters.Resolution do
  @moduledoc """
  Random resolution of pending progression choices: repeatedly picking a
  resolvable entry from `Characters.Progression.pending_choices/3` and
  applying a random selection (or die roll for value progressions) until
  none remain.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.auto_resolve_pending/2`); this module hosts
  the implementation.
  """

  alias DiceLib.Basic, as: Dice
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Decision
  alias ExTTRPGDev.Characters.Effects
  alias ExTTRPGDev.Characters.Progression
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystem.Expression
  alias ExTTRPGDev.RuleSystem.Vocabulary
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  # Bound to an attribute for use in pattern-match positions; the name is
  # owned by ExTTRPGDev.RuleSystem.Vocabulary.
  @progression_type Vocabulary.progression_type()

  @doc """
  Randomly resolves all pending progression choices earned at level 1.

  See `ExTTRPGDev.Characters.auto_resolve_pending/2` for documentation.
  """
  def auto_resolve_pending(%LoadedSystem{} = system, %Character{} = character) do
    {resolved, _resolutions} =
      resolve_all(system, character, &resolvable_at_level_1?/1, &rolled_value_method/1, [])

    resolved
  end

  @doc """
  Randomly resolves all pending progression choices for a character, regardless of level.

  See `ExTTRPGDev.Characters.random_resolve_all/2` for documentation.
  """
  def random_resolve_all(%LoadedSystem{} = system, %Character{} = character) do
    resolve_all(system, character, &resolvable?/1, &random_value_method/1, [])
  end

  defp resolvable_at_level_1?(%{type: :pending, options: [], earned_at_level: level})
       when level in [nil, 1],
       do: false

  defp resolvable_at_level_1?(%{type: :pending, earned_at_level: level})
       when level in [nil, 1],
       do: true

  defp resolvable_at_level_1?(_), do: false

  defp resolvable?(%{type: :pending, options: [_ | _]}), do: true
  defp resolvable?(%{type: :pending, options: []}), do: false
  defp resolvable?(%{type: :pending, roll: roll}) when is_binary(roll), do: true
  defp resolvable?(_), do: false

  defp resolve_all(
         %LoadedSystem{} = system,
         %Character{} = character,
         resolvable?,
         value_method,
         acc
       ) do
    {_effects, resolved} = Effects.resolved_state(system, character)
    choices = Progression.pending_choices(system, character, resolved)

    case Enum.find(choices, resolvable?) do
      nil ->
        {character, Enum.reverse(acc)}

      entry ->
        {updated, resolution} = apply_resolution(system, entry, character, value_method)
        resolve_all(system, updated, resolvable?, value_method, [resolution | acc])
    end
  end

  defp apply_resolution(system, %{type: :pending} = entry, character, value_method) do
    cond do
      Map.has_key?(entry, :scope_type) -> resolve_sub_choice(system, entry, character)
      Map.has_key?(entry, :options) -> resolve_selection(system, entry, character)
      true -> resolve_value(entry, character, value_method)
    end
  end

  defp resolve_sub_choice(system, entry, character) do
    selection = Enum.random(entry.options)

    decision = %Decision{
      scope: {entry.scope_type, entry.scope_id},
      choice: entry.id,
      selection: selection
    }

    updated = %{character | decisions: character.decisions ++ [decision]}

    concept_type =
      get_in(system.concept_metadata, [
        {entry.scope_type, entry.scope_id},
        "choices",
        entry.id,
        "type"
      ])

    resolution = %{
      name: entry.name,
      concept_type: concept_type,
      selection_id: selection,
      rolled_value: nil,
      method: nil,
      earned_at_level: Map.get(entry, :earned_at_level)
    }

    {updated, resolution}
  end

  defp resolve_selection(system, entry, character) do
    selection = Enum.random(entry.options)
    decision = Progression.next_progression_decision(character.decisions, entry.id, selection)
    updated = %{character | decisions: character.decisions ++ [decision]}
    meta = system.concept_metadata[{@progression_type, entry.id}]

    resolution = %{
      name: entry.name,
      concept_type: meta && meta["type"],
      selection_id: selection,
      rolled_value: nil,
      method: nil,
      earned_at_level: Map.get(entry, :earned_at_level)
    }

    {updated, resolution}
  end

  defp resolve_value(entry, character, value_method) do
    {method, value} = value_method.(entry.roll)
    [node_key | _] = Expression.extract_refs(entry.effect_target)

    decision = Progression.next_progression_decision(character.decisions, entry.id, method)
    effect = %Effect{target: node_key, value: value}

    updated = %{
      character
      | decisions: character.decisions ++ [decision],
        effects: character.effects ++ [effect]
    }

    resolution = %{
      name: entry.name,
      concept_type: nil,
      selection_id: nil,
      rolled_value: value,
      method: method,
      earned_at_level: Map.get(entry, :earned_at_level)
    }

    {updated, resolution}
  end

  defp rolled_value_method(die_str) do
    {"rolled", Dice.roll("1#{die_str}") |> Enum.sum()}
  end

  defp random_value_method(die_str) do
    sides = die_str |> String.trim_leading("d") |> String.to_integer()
    average = div(sides, 2) + 1

    if :rand.uniform(2) == 1 do
      rolled_value_method(die_str)
    else
      {"average", average}
    end
  end
end
