defmodule ExTTRPGDev.Characters.Progression do
  @moduledoc """
  Pending progression-choice machinery: computing which progression choices
  are pending or available for a character, tracking the choice slots
  unlocked by level, and filtering the valid options for each choice.

  `pending_choices/3` and `compute_pending_choice_slots/2` evaluate
  rule-system-authored expressions (`required_count`, `available_when`,
  `filter.max_level_node`, `module.level_node`). A malformed expression is
  reported as a structured entry in the result's `:errors` list rather than
  raising or silently treating the affected progression as having nothing
  pending — every other, well-formed progression still resolves normally.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.pending_choices/3`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.ClassLevels
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
  Returns the pending/available progression choices for a character, along
  with any expression-evaluation errors encountered while computing them.

  See `ExTTRPGDev.Characters.pending_choices/3` for documentation.
  """
  def pending_choices(%LoadedSystem{} = system, %Character{} = character, resolved) do
    active = Effects.active_concepts(system, character)

    {progression_choices, errors} =
      system.concept_metadata
      |> Enum.filter(fn {{type, _id}, _} -> type == @progression_type end)
      |> Enum.reduce({[], []}, fn {{_type, id}, meta}, {choices_acc, errors_acc} ->
        roll = resolve_roll_reference(meta["roll_reference"], id, character, system)
        meta_with_roll = Map.put(meta, "roll", roll)

        {choices, choice_errors} =
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

        {choices_acc ++ choices, errors_acc ++ choice_errors}
      end)

    sub_choices = pending_sub_choices(character.decisions, system.concept_metadata)
    class_choices = pending_additional_class_choices(system, character)

    choices =
      (progression_choices ++ sub_choices ++ class_choices)
      |> Enum.sort_by(& &1.id)

    {:ok, %{choices: choices, errors: errors}}
  end

  @doc """
  Computes the pending selection progression choice slots for a character,
  along with any expression-evaluation errors encountered while computing
  them.

  See `ExTTRPGDev.Characters.compute_pending_choice_slots/2` for documentation.
  """
  def compute_pending_choice_slots(%LoadedSystem{} = system, %Character{} = character) do
    with level_node when not is_nil(level_node) <- system.module.level_node,
         [level_node_key | _] <- Expression.extract_refs(level_node) do
      slots_from_level_node(system, character, level_node_key)
    else
      nil ->
        {:ok, %{slots: [], errors: []}}

      [] ->
        error = %{
          progression_id: nil,
          field: "module.level_node",
          expr: system.module.level_node,
          reason: :no_node_references
        }

        {:ok, %{slots: [], errors: [error]}}
    end
  end

  defp slots_from_level_node(system, character, level_node_key) do
    {_effects, resolved} = Effects.resolved_state(system, character)
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
        # A class taken later isn't held yet at this level, so its effects
        # mustn't count towards slots earned here.
        at_level = ClassLevels.as_of_level(character, level)

        {level,
         Leveling.evaluate_at_level(
           system,
           at_level,
           level,
           thresholds,
           xp_target,
           Effects.active_effects(system, at_level)
         )}
      end)

    {slots, errors} =
      Enum.reduce(selection_progressions, {[], []}, fn {{_type, id}, meta},
                                                       {slots_acc, errors_acc} ->
        decisions_made = count_progression_decisions(character.decisions, id)
        {slots, slot_errors} = slots_for_progression(id, meta, level_resolved, current_level)

        {slots_acc ++ Enum.drop(slots, decisions_made), errors_acc ++ slot_errors}
      end)

    {:ok, %{slots: slots, errors: Enum.uniq(errors)}}
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
    required_label = {progression_id, "required_count"}
    max_level_label = {progression_id, "filter.max_level_node"}

    Enum.reduce(1..current_level, {[], []}, fn level, {slots_acc, errors_acc} ->
      resolved_at = level_resolved[level]

      {count_at, err1} = eval_int(required_str, resolved_at, required_label)

      {count_at_prev, err2} =
        if level > 1,
          do: eval_int(required_str, level_resolved[level - 1], required_label),
          else: {0, []}

      {max_level_cap, err3} = eval_int(max_level_node, resolved_at, max_level_label)

      new_slots =
        List.duplicate(
          %{progression_id: progression_id, earned_at_level: level, max_level_cap: max_level_cap},
          max(0, count_at - count_at_prev)
        )

      {slots_acc ++ new_slots, errors_acc ++ err1 ++ err2 ++ err3}
    end)
  end

  defp eval_int(expr, resolved, {progression_id, field}) do
    case Expression.evaluate(expr, resolved) do
      {:ok, v} ->
        {trunc(v), []}

      {:error, reason} ->
        error = %{progression_id: progression_id, field: field, expr: expr, reason: reason}
        {0, [error]}
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

  # A class taken after the first makes only the sub-choices its multiclass
  # table lists under `choices` (e.g. one skill instead of a first class's
  # two), each once. Choices granting inventory are starting equipment,
  # which a multiclassed class doesn't get.
  defp pending_additional_class_choices(system, character) do
    system
    |> ClassLevels.additional_classes(character)
    |> Enum.flat_map(fn {type, id} ->
      meta = Map.get(system.concept_metadata, {type, id}, %{})
      allowed = get_in(meta, [Vocabulary.multiclass_key(), "choices"]) || []

      meta
      |> Map.get("choices", %{})
      |> Enum.filter(fn {choice_id, choice_def} ->
        choice_id in allowed and choice_def["grants_to"] != "inventory"
      end)
      |> Enum.flat_map(
        &pending_choice_entry(&1, character.decisions, system.concept_metadata, type, id, 1)
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
      options = sub_choice_options(choice_def, concept_metadata)

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

  # A choice's explicit `options` list wins; without one, every concept of
  # the choice's type is eligible. Mirrors Advancement.sub_choice_options/2,
  # which resolving the choice validates against.
  defp sub_choice_options(%{"options" => options}, _concept_metadata) when is_list(options),
    do: options

  defp sub_choice_options(choice_def, concept_metadata) do
    concept_metadata
    |> Enum.filter(fn {{t, _cid}, _} -> t == choice_def["type"] end)
    |> Enum.map(fn {{_t, cid}, _} -> cid end)
    |> Enum.sort()
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
    case Expression.evaluate(required_str, resolved) do
      {:ok, required} ->
        made = count_progression_decisions(decisions, id)
        pending_count = max(0, trunc(required) - made)

        if pending_count > 0 do
          entry =
            selection_progression_entry(
              id,
              meta,
              decisions,
              resolved,
              concept_metadata,
              active,
              pending_choice_slots,
              pending_count
            )

          {[entry], []}
        else
          {[], []}
        end

      {:error, reason} ->
        {[], [required_count_error(id, required_str, reason)]}
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
       do: {[], []}

  defp selection_progression_entry(
         id,
         meta,
         decisions,
         resolved,
         concept_metadata,
         active,
         pending_choice_slots,
         pending_count
       ) do
    already_selected =
      decisions
      |> Enum.filter(fn d -> d.scope == {@progression_type, id} end)
      |> MapSet.new(& &1.selection)

    {max_level_cap, earned_at_level} = find_next_slot(pending_choice_slots, id)
    capped_resolved = apply_slot_cap(resolved, meta, max_level_cap)

    options =
      concept_options(meta, concept_metadata, active, capped_resolved)
      |> Enum.reject(&MapSet.member?(already_selected, &1))

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
  end

  defp required_count_error(id, expr, reason),
    do: %{progression_id: id, field: "required_count", expr: expr, reason: reason}

  defp available_when_error(id, expr, reason),
    do: %{progression_id: id, field: "available_when", expr: expr, reason: reason}

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
    case Expression.evaluate(required_str, resolved) do
      {:ok, required} ->
        made = count_progression_decisions(decisions, id)
        pending_count = max(0, trunc(required) - made)

        if pending_count > 0 do
          entry = %{
            type: :pending,
            id: id,
            name: meta["name"] || id,
            count: pending_count,
            effect_target: meta["effect_target"],
            roll: meta["roll"]
          }

          {[entry], []}
        else
          {[], []}
        end

      {:error, reason} ->
        {[], [required_count_error(id, required_str, reason)]}
    end
  end

  defp progression_choices(id, %{"available_when" => available_str} = meta, _decisions, resolved) do
    case Expression.evaluate(available_str, resolved) do
      {:ok, val} when val not in [0, false, nil] ->
        entry = %{
          type: :available,
          id: id,
          name: meta["name"] || id,
          effect_target: meta["effect_target"],
          roll: meta["roll"]
        }

        {[entry], []}

      {:ok, _falsy} ->
        {[], []}

      {:error, reason} ->
        {[], [available_when_error(id, available_str, reason)]}
    end
  end

  defp progression_choices(_id, _meta, _decisions, _resolved), do: {[], []}

  defp count_progression_decisions(decisions, progression_id) do
    Enum.count(decisions, fn
      %Decision{scope: {@progression_type, ^progression_id}} -> true
      _ -> false
    end)
  end

  defp resolve_roll_reference(nil, _progression_id, _character, _system), do: nil

  defp resolve_roll_reference(roll_reference, progression_id, character, system) do
    case String.split(roll_reference, ".", parts: 2) do
      [type_id, field] ->
        case referenced_concept(type_id, progression_id, character, system) do
          nil -> nil
          concept_id -> get_in(system.concept_metadata, [{type_id, concept_id}, field])
        end

      _ ->
        nil
    end
  end

  # The concept of `type_id` a roll reference reads: the root decision of
  # that type. For the class concept type with class levels, it's the class
  # that gained the level the next decision is for, taking the
  # progression's decisions as one per level after the first (decision n is
  # for level n + 1), as a per-level hit point roll is.
  defp referenced_concept(type_id, progression_id, character, system) do
    if type_id == ClassLevels.class_type(system) do
      level = count_progression_decisions(character.decisions, progression_id) + 2
      ClassLevels.class_at_level(system, character, level)
    else
      Enum.find_value(character.decisions, fn
        %Decision{scope: nil, choice: ^type_id, selection: concept_id} -> concept_id
        _ -> nil
      end)
    end
  end
end
