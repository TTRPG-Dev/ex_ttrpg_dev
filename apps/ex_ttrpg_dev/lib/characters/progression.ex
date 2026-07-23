defmodule ExTTRPGDev.Characters.Progression do
  @moduledoc """
  Pending progression-choice machinery: computing which progression choices
  are pending or available for a character, tracking the choice slots
  unlocked by level, and filtering the valid options for each choice.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.pending_choices/3`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Decision
  alias ExTTRPGDev.Characters.Effects
  alias ExTTRPGDev.Characters.Leveling
  alias ExTTRPGDev.RuleSystem.Expression
  alias ExTTRPGDev.RuleSystem.Vocabulary
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  # Bound to an attribute for use in pattern-match positions; the name is
  # owned by ExTTRPGDev.RuleSystem.Vocabulary.
  @progression_type Vocabulary.progression_type()

  @doc """
  Returns the list of character progression choices that are currently pending or available.

  See `ExTTRPGDev.Characters.pending_choices/3` for documentation.
  """
  def pending_choices(%LoadedSystem{} = system, %Character{} = character, resolved) do
    active = Effects.active_concepts(character.decisions, system.concept_metadata)

    progression_choices =
      system.concept_metadata
      |> Enum.filter(fn {{type, _id}, _} -> type == @progression_type end)
      |> Enum.flat_map(fn {{_type, id}, meta} ->
        roll = resolve_roll_reference(meta["roll_reference"], character, system.concept_metadata)
        meta_with_roll = Map.put(meta, "roll", roll)

        if Map.has_key?(meta, "type") do
          selection_progression_choices(
            id,
            meta_with_roll,
            character.decisions,
            resolved,
            system.concept_metadata,
            active,
            character.pending_choice_slots
          )
        else
          progression_choices(id, meta_with_roll, character.decisions, resolved)
        end
      end)

    sub_choices = pending_sub_choices(character.decisions, system.concept_metadata)

    (progression_choices ++ sub_choices)
    |> Enum.sort_by(& &1.id)
  end

  @doc """
  Computes the list of pending selection progression choice slots for a character.

  See `ExTTRPGDev.Characters.compute_pending_choice_slots/2` for documentation.
  """
  def compute_pending_choice_slots(%LoadedSystem{} = system, %Character{} = character) do
    with level_node when not is_nil(level_node) <- system.module.level_node,
         [level_node_key | _] <- Expression.extract_refs(level_node) do
      {all_effects, resolved} = Effects.resolved_state(system, character)
      current_level = trunc(resolved[level_node_key] || 1)

      thresholds = Leveling.level_xp_thresholds(system)
      xp_target = Leveling.xp_effect_target(system)

      selection_progressions =
        Enum.filter(system.concept_metadata, fn {{type, _id}, meta} ->
          type == @progression_type and
            Map.has_key?(meta, "type") and
            get_in(meta, ["filter", "max_level_node"]) != nil
        end)

      level_resolved =
        Map.new(1..current_level, fn level ->
          {level,
           Leveling.evaluate_at_level(
             system,
             character,
             level,
             thresholds,
             xp_target,
             all_effects
           )}
        end)

      Enum.flat_map(selection_progressions, fn {{_type, id}, meta} ->
        decisions_made = count_progression_decisions(character.decisions, id)

        slots_for_progression(id, meta, level_resolved, current_level)
        |> Enum.drop(decisions_made)
      end)
    else
      _ -> []
    end
  end

  @doc """
  Returns the concept IDs that are valid options for a selection progression.

  See `ExTTRPGDev.Characters.concept_options/4` for documentation.
  """
  def concept_options(meta, concept_metadata, active, resolved) do
    filter = meta["filter"] || %{}
    concept_type = meta["type"]
    level_fn = level_filter(filter, resolved)
    active_in = filter["active_in"]

    concept_metadata
    |> Enum.filter(fn {{type, _id}, concept_meta} ->
      type == concept_type and
        level_fn.(concept_meta["level"] || 0) and
        passes_active_in_filter?(concept_meta, active_in, active) and
        passes_requires?(concept_meta["requires"], resolved)
    end)
    |> Enum.map(fn {{_type, id}, _} -> id end)
    |> Enum.sort()
  end

  @doc """
  Overrides the `max_level_node` binding in `resolved` with `cap`.

  See `ExTTRPGDev.Characters.apply_slot_cap/3` for documentation.
  """
  def apply_slot_cap(resolved, _meta, nil), do: resolved

  def apply_slot_cap(resolved, meta, cap) do
    max_level_node = get_in(meta, ["filter", "max_level_node"])

    case max_level_node && Expression.extract_refs(max_level_node) do
      [node_key | _] -> Map.put(resolved, node_key, cap)
      _ -> resolved
    end
  end

  @doc """
  The single constructor for progression decisions.

  See `ExTTRPGDev.Characters.next_progression_decision/3` for documentation.
  """
  def next_progression_decision(decisions, progression_id, selection) do
    n = count_progression_decisions(decisions, progression_id) + 1

    %Decision{
      scope: Vocabulary.progression_scope(progression_id),
      choice: Vocabulary.progression_choice_id(n),
      selection: selection
    }
  end

  defp slots_for_progression(progression_id, meta, level_resolved, current_level) do
    required_str = meta["required_count"]
    max_level_node = get_in(meta, ["filter", "max_level_node"])

    Enum.flat_map(1..current_level, fn level ->
      resolved_at = level_resolved[level]

      count_at = eval_int(required_str, resolved_at)
      count_at_prev = if level > 1, do: eval_int(required_str, level_resolved[level - 1]), else: 0
      max_level_cap = eval_int(max_level_node, resolved_at)

      List.duplicate(
        %{progression_id: progression_id, earned_at_level: level, max_level_cap: max_level_cap},
        max(0, count_at - count_at_prev)
      )
    end)
  end

  defp eval_int(expr, resolved) do
    case Expression.evaluate(expr, resolved) do
      {:ok, v} -> trunc(v)
      _ -> 0
    end
  end

  defp pending_sub_choices(decisions, concept_metadata) do
    # Collect all selections made via character_progression decisions, grouped by {type, id}.
    # The progression's "type" field tells us which concept type was selected.
    progression_type_map =
      concept_metadata
      |> Enum.filter(fn {{type, _id}, meta} ->
        type == @progression_type and Map.has_key?(meta, "type")
      end)
      |> Map.new(fn {{_type, id}, meta} -> {id, meta["type"]} end)

    selection_counts =
      decisions
      |> Enum.filter(fn d ->
        case d.scope do
          {@progression_type, prog_id} -> Map.has_key?(progression_type_map, prog_id)
          _ -> false
        end
      end)
      |> Enum.reduce(%{}, fn d, acc ->
        {@progression_type, prog_id} = d.scope
        concept_type = Map.fetch!(progression_type_map, prog_id)
        Map.update(acc, {concept_type, d.selection}, 1, &(&1 + 1))
      end)

    Enum.flat_map(selection_counts, fn {{type, id}, selected_count} ->
      choices = get_in(concept_metadata, [{type, id}, "choices"]) || %{}

      Enum.flat_map(
        choices,
        &pending_choice_entry(&1, decisions, concept_metadata, type, id, selected_count)
      )
    end)
  end

  defp pending_choice_entry(
         {choice_id, choice_def},
         decisions,
         concept_metadata,
         type,
         id,
         selected_count
       ) do
    resolved_count = Enum.count(decisions, &(&1.scope == {type, id} and &1.choice == choice_id))
    pending_count = max(0, selected_count - resolved_count)

    if pending_count > 0 do
      options =
        concept_metadata
        |> Enum.filter(fn {{t, _cid}, _} -> t == choice_def["type"] end)
        |> Enum.map(fn {{_t, cid}, _} -> cid end)
        |> Enum.sort()

      [
        %{
          type: :pending,
          id: choice_id,
          scope_type: type,
          scope_id: id,
          name: choice_def["name"] || choice_id,
          count: pending_count,
          earned_at_level: nil,
          options: options
        }
      ]
    else
      []
    end
  end

  defp selection_progression_choices(
         id,
         %{"required_count" => required_str} = meta,
         decisions,
         resolved,
         concept_metadata,
         active,
         pending_choice_slots
       ) do
    with {:ok, required} <- Expression.evaluate(required_str, resolved),
         made = count_progression_decisions(decisions, id),
         pending_count = max(0, trunc(required) - made),
         true <- pending_count > 0 do
      already_selected =
        decisions
        |> Enum.filter(fn d -> d.scope == {@progression_type, id} end)
        |> MapSet.new(& &1.selection)

      {max_level_cap, earned_at_level} = find_next_slot(pending_choice_slots, id)
      capped_resolved = apply_slot_cap(resolved, meta, max_level_cap)

      options =
        concept_options(meta, concept_metadata, active, capped_resolved)
        |> Enum.reject(&MapSet.member?(already_selected, &1))

      [
        %{
          type: :pending,
          id: id,
          name: meta["name"] || id,
          count: pending_count,
          effect_target: nil,
          roll: nil,
          earned_at_level: earned_at_level,
          options: options
        }
      ]
    else
      _ -> []
    end
  end

  defp selection_progression_choices(
         _id,
         _meta,
         _decisions,
         _resolved,
         _concept_metadata,
         _active,
         _pending_choice_slots
       ),
       do: []

  defp passes_requires?(nil, _resolved), do: true

  defp passes_requires?(requires, resolved) do
    Enum.all?(requires, fn %{"node" => node, "min" => min} ->
      case Expression.evaluate(node, resolved) do
        {:ok, val} -> val >= min
        _ -> false
      end
    end)
  end

  defp passes_active_in_filter?(_meta, nil, _active), do: true

  defp passes_active_in_filter?(meta, %{"field" => field, "type" => type}, active) do
    Enum.any?(meta[field] || [], fn id -> MapSet.member?(active, {type, id}) end)
  end

  defp level_filter(%{"level" => exact_level}, _resolved) do
    fn level -> level == exact_level end
  end

  defp level_filter(%{"min_level" => min, "max_level_node" => max_node}, resolved) do
    max_level =
      case Expression.evaluate(max_node, resolved) do
        {:ok, val} -> trunc(val)
        _ -> 0
      end

    fn level -> level >= min and level <= max_level end
  end

  defp level_filter(_filter, _resolved), do: fn _level -> true end

  defp find_next_slot(pending_choice_slots, progression_id) do
    case Enum.find(pending_choice_slots, &(&1.progression_id == progression_id)) do
      %{max_level_cap: cap, earned_at_level: level} -> {cap, level}
      nil -> {nil, nil}
    end
  end

  defp progression_choices(id, %{"required_count" => required_str} = meta, decisions, resolved) do
    with {:ok, required} <- Expression.evaluate(required_str, resolved),
         made = count_progression_decisions(decisions, id),
         pending_count = max(0, trunc(required) - made),
         true <- pending_count > 0 do
      [
        %{
          type: :pending,
          id: id,
          name: meta["name"] || id,
          count: pending_count,
          effect_target: meta["effect_target"],
          roll: meta["roll"]
        }
      ]
    else
      _ -> []
    end
  end

  defp progression_choices(id, %{"available_when" => available_str} = meta, _decisions, resolved) do
    case Expression.evaluate(available_str, resolved) do
      {:ok, val} when val not in [0, false, nil] ->
        [
          %{
            type: :available,
            id: id,
            name: meta["name"] || id,
            effect_target: meta["effect_target"],
            roll: meta["roll"]
          }
        ]

      _ ->
        []
    end
  end

  defp progression_choices(_id, _meta, _decisions, _resolved), do: []

  defp count_progression_decisions(decisions, progression_id) do
    Enum.count(decisions, fn
      %Decision{scope: {@progression_type, ^progression_id}} -> true
      _ -> false
    end)
  end

  defp resolve_roll_reference(nil, _character, _concept_metadata), do: nil

  defp resolve_roll_reference(roll_reference, character, concept_metadata) do
    case String.split(roll_reference, ".", parts: 2) do
      [type_id, field] ->
        case Enum.find(character.decisions, &(&1.scope == nil and &1.choice == type_id)) do
          nil -> nil
          %{selection: concept_id} -> get_in(concept_metadata, [{type_id, concept_id}, field])
        end

      _ ->
        nil
    end
  end
end
