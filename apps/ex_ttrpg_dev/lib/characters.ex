defmodule ExTTRPGDev.Characters do
  @moduledoc """
  This module handles handles character operations
  """
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Metadata
  alias ExTTRPGDev.Characters.InventoryItem
  alias ExTTRPGDev.Dice
  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.RuleSystem.Evaluator
  alias ExTTRPGDev.RuleSystem.Expression
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Get the file path for a character

  ## Examples

      iex> Characters.character_file_path!(%Character{metadata: %Characters.Metadata{slug: "mr_whiskers"}})
      "mr_whiskers.json"
  """
  def character_file_path!(%Character{metadata: %Metadata{slug: slug}}) do
    character_file_path!(slug)
  end

  def character_file_path!(character_slug) when is_bitstring(character_slug) do
    Path.join(Globals.characters_path(), "#{character_slug}.json")
  end

  @doc """
  Returns a boolean as to whether the character exists on disk

  ## Examples

      iex> Characters.character_exists?(%Characters.Character{name: "This Character exists"})
      true

      iex> Characters.character_exists?("this_character_exists")
      true

      iex> Characters.Character_exists?(%Characters.Character{name: "This character doesn't exist})
      false

      iex> Characters.Character_exists?("this_character_doesnt_exist")
      false
  """
  def character_exists?(character) do
    character
    |> character_file_path!
    |> File.exists?()
  end

  @doc """
  Saves the given character to disk. Error is raised if character already exists unless `overwrite` is set to true

  ## Example

      iex> Characters.save_character!(%Characters.Character{name: "doesn't exist yet"})
      :ok

      iex> Characters.save_character!(%Characters.Character{name: "exists already"})
      :error, :character already exists

      iex> Characters.save_character!(%Characters.Character{name: "exists already"}, true)
      :ok
  """
  def save_character!(
        %Character{} = character,
        overwrite \\ false
      ) do
    if character_exists?(character) and not overwrite do
      raise "Character named #{character.name} already exsts. To overwrite, pass `overwrite` as true"
    else
      File.mkdir_p!(Globals.characters_path())

      File.write!(
        character_file_path!(character),
        Poison.encode!(Character.to_json_map(character))
      )
    end
  end

  @doc """
  Delete a saved character by slug.

  Returns `:ok` if the character was deleted, `{:error, :not_found}` if no
  character with that slug exists.
  """
  def delete_character(character_slug) do
    path = character_file_path!(character_slug)

    if File.exists?(path) do
      File.rm!(path)
      :ok
    else
      {:error, :not_found}
    end
  end

  @doc """
  List saved characters

  ## Example

      iex> Characters.list_characters!()
      [%Character{}, %Character{}, ...]
  """
  def list_characters!() do
    if File.exists?(Globals.characters_path()) do
      File.ls!(Globals.characters_path())
      |> Enum.map(fn x -> String.trim_trailing(x, ".json") end)
    else
      []
    end
  end

  @doc """
  Load a saved character

  ## Example

      iex> Character.load_character!("misu_park_the_cat")
      %Character{}
  """
  def load_character!(character_slug) do
    character_file_path!(character_slug)
    |> File.read!()
    |> Character.from_json!()
  end

  @doc """
  Generates a random decision list for a system by randomly selecting a value for each required
  character choice and recursing into any sub-choices declared by the selected concept.

  Root concepts (those not referenced as sub-options of any other concept of the same type)
  are the valid top-level picks. Sub-choices follow whatever options the selected concept declares.
  """
  def random_decisions(%LoadedSystem{} = system) do
    system.module.character_building_choices
    |> Enum.flat_map(fn %{concept_type: type_id} ->
      root_ids = root_concept_ids(system.concept_metadata, type_id)
      selected_id = Enum.random(root_ids)
      decision = %{scope: nil, choice: type_id, selection: selected_id}
      [decision | random_sub_decisions(system.concept_metadata, {type_id, selected_id})]
    end)
  end

  @doc """
  Returns the XP needed for a character to reach the next level in the given system.

  Returns `{:ok, xp_needed, next_level}` when a next level exists, or `{:error, :max_level}`
  if the character is already at the highest level defined by the system.

  Returns `{:error, :no_level_thresholds}` if the system does not define a level mapping.
  """
  def xp_to_next_level(%LoadedSystem{} = system, %Character{} = character) do
    thresholds = level_xp_thresholds(system)

    if map_size(thresholds) == 0 do
      {:error, :no_level_thresholds}
    else
      xp_target = xp_effect_target(system)

      current_xp =
        character.effects
        |> Enum.filter(&(&1.target == xp_target))
        |> Enum.map(& &1.value)
        |> Enum.sum()

      current_level =
        thresholds
        |> Enum.filter(fn {_level, threshold} -> threshold <= current_xp end)
        |> Enum.max_by(fn {_level, threshold} -> threshold end, fn -> nil end)
        |> case do
          nil -> 1
          {level, _} -> level
        end

      next_level =
        thresholds
        |> Map.keys()
        |> Enum.sort()
        |> Enum.find(&(&1 > current_level))

      if is_nil(next_level) do
        {:error, :max_level}
      else
        {:ok, Map.fetch!(thresholds, next_level) - current_xp, next_level}
      end
    end
  end

  @doc """
  Returns the set of active `{type_id, concept_id}` pairs derived from a character's decisions.

  Walks the decisions tree starting from root decisions (scope: nil), adding each selected
  concept and recursing into any sub-choices that concept declares.
  """
  def active_concepts(decisions, concept_metadata) do
    decisions
    |> Enum.filter(fn d -> d.scope == nil end)
    |> Enum.reduce(MapSet.new(), fn %{choice: type, selection: id}, acc ->
      collect_active_concepts({type, id}, decisions, concept_metadata, acc)
    end)
  end

  @doc """
  Returns the combined effects list for a character against a system.

  Filters system-defined effects to only those whose source concept is active
  (per the character's decisions), then appends the character's own effects.
  """
  def active_effects(%LoadedSystem{} = system, %Character{} = character) do
    active = active_concepts(character.decisions, system.concept_metadata)
    decision_effects = effects_from_decisions(character.decisions, system.concept_metadata)

    system.effects
    |> Enum.filter(fn
      %{source: {type, id}} -> MapSet.member?(active, {type, id})
      %{source: {type, id, _}} -> MapSet.member?(active, {type, id})
      _ -> false
    end)
    |> Kernel.++(decision_effects)
    |> Kernel.++(inventory_effects(system, character.inventory))
    |> Kernel.++(character.effects)
  end

  @doc """
  Rolls for a concept using the roll definition attached to its type in the system config.

  Looks up a roll definition (from the system's `roll` concept type) whose `target_type`
  matches `type_id`, then rolls the specified dice and adds the resolved value of
  `bonus_field` for the given concept.

  Returns a map with `:type_id`, `:concept_id`, `:dice` (spec string), `:rolls` (list of
  individual die results), `:bonus`, and `:total`.

  Raises if no roll is defined for the given concept type, or if the bonus field cannot
  be resolved for the concept.
  """
  def concept_roll!(%LoadedSystem{} = system, %Character{} = character, type_id, concept_id) do
    roll_def =
      system.concept_metadata
      |> Enum.find(fn {{type, _id}, meta} ->
        type == "roll" and meta["target_type"] == type_id
      end)

    unless roll_def do
      raise "No roll defined for concept type \"#{type_id}\" in system \"#{system.module.slug}\""
    end

    {_key, %{"dice" => dice_str, "bonus_field" => bonus_field}} = roll_def

    effects = active_effects(system, character)
    resolved = Evaluator.evaluate!(system, character.generated_values, effects)

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

  @doc """
  Returns the list of character progression choices that are currently pending or available.

  Each entry is a map with:
  - `:type` — `:pending` (required and not yet made) or `:available` (optional and currently unlocked)
  - `:id` — the progression concept id
  - `:name` — display name
  - `:effect_target` — where the resulting value should be applied (e.g. `"character_trait('max_hit_points').points"`)
  - `:roll` — the resolved roll reference (e.g. `"d8"`), or `nil` if none

  For `:pending` entries, `:count` is also included indicating how many choices remain.

  `resolved` should be the output of `Evaluator.evaluate!/3` for the character's current state.
  """
  def pending_choices(%LoadedSystem{} = system, %Character{} = character, resolved) do
    active = active_concepts(character.decisions, system.concept_metadata)

    progression_choices =
      system.concept_metadata
      |> Enum.filter(fn {{type, _id}, _} -> type == "character_progression" end)
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
  Randomly resolves all pending progression choices earned at level 1.

  Intended to be called immediately after `Character.gen_character!/2` so that
  the returned character has no level-1 pending choices. Choices earned at higher
  levels (tracked in `pending_choice_slots`) are left untouched for manual resolution.

  - Selection progressions (cantrips, spells known) pick a random valid option.
  - Value progressions (HP) roll the associated die.
  - Sub-choices are picked randomly from their declared options.

  Loops until `pending_choices/3` returns no resolvable level-1 entries.
  """
  def auto_resolve_pending(%LoadedSystem{} = system, %Character{} = character) do
    all_effects = active_effects(system, character)
    resolved = Evaluator.evaluate!(system, character.generated_values, all_effects)
    choices = pending_choices(system, character, resolved)

    case Enum.find(choices, &resolvable_at_level_1?/1) do
      nil ->
        character

      entry ->
        character |> apply_auto_resolution(entry) |> then(&auto_resolve_pending(system, &1))
    end
  end

  defp resolvable_at_level_1?(%{type: :pending, options: [], earned_at_level: level})
       when level in [nil, 1],
       do: false

  defp resolvable_at_level_1?(%{type: :pending, earned_at_level: level})
       when level in [nil, 1],
       do: true

  defp resolvable_at_level_1?(_), do: false

  defp apply_auto_resolution(character, %{type: :pending} = entry) do
    cond do
      Map.has_key?(entry, :scope_type) -> apply_auto_sub_choice(character, entry)
      Map.has_key?(entry, :options) -> apply_auto_selection(character, entry)
      true -> apply_auto_value(character, entry)
    end
  end

  defp apply_auto_selection(character, %{id: prog_id, options: options}) do
    n = count_progression_decisions(character.decisions, prog_id) + 1

    decision = %{
      scope: {"character_progression", prog_id},
      choice: "choice_#{n}",
      selection: Enum.random(options)
    }

    %{character | decisions: character.decisions ++ [decision]}
  end

  defp apply_auto_sub_choice(character, %{
         id: choice_id,
         scope_type: st,
         scope_id: si,
         options: opts
       }) do
    decision = %{scope: {st, si}, choice: choice_id, selection: Enum.random(opts)}
    %{character | decisions: character.decisions ++ [decision]}
  end

  defp apply_auto_value(character, %{id: prog_id, effect_target: target_str, roll: roll}) do
    n = count_progression_decisions(character.decisions, prog_id) + 1
    [node_key | _] = Expression.extract_refs(target_str)
    value = Dice.roll("1#{roll}") |> Enum.sum()

    decision = %{
      scope: {"character_progression", prog_id},
      choice: "choice_#{n}",
      selection: "rolled"
    }

    effect = %{target: node_key, value: value}

    %{
      character
      | decisions: character.decisions ++ [decision],
        effects: character.effects ++ [effect]
    }
  end

  @doc """
  Randomly resolves all pending progression choices for a character, regardless of level.

  Returns `{updated_character, resolutions}` where `resolutions` is a list of maps
  describing each resolved choice:

  - Selection progressions: `%{name, concept_type, selection_id, rolled_value: nil, method: nil, earned_at_level}`
  - Value progressions: `%{name, concept_type: nil, selection_id: nil, rolled_value, method, earned_at_level}`

  Intended for the `--random-resolve` CLI flag. Choices with no available options are skipped.
  Value progressions randomly choose between "rolled" (actual dice roll) and "average" (sides/2 + 1).
  """
  def random_resolve_all(%LoadedSystem{} = system, %Character{} = character) do
    do_random_resolve_all(system, character, [])
  end

  defp do_random_resolve_all(%LoadedSystem{} = system, %Character{} = character, acc) do
    all_effects = active_effects(system, character)
    resolved = Evaluator.evaluate!(system, character.generated_values, all_effects)
    choices = pending_choices(system, character, resolved)

    case Enum.find(choices, &resolvable?/1) do
      nil ->
        {character, Enum.reverse(acc)}

      entry ->
        {updated, resolution} = apply_tracked_resolution(system, entry, character)
        do_random_resolve_all(system, updated, [resolution | acc])
    end
  end

  defp resolvable?(%{type: :pending, options: [_ | _]}), do: true
  defp resolvable?(%{type: :pending, options: []}), do: false
  defp resolvable?(%{type: :pending, roll: roll}) when is_binary(roll), do: true
  defp resolvable?(_), do: false

  defp apply_tracked_resolution(system, %{type: :pending} = entry, character) do
    cond do
      Map.has_key?(entry, :scope_type) -> track_sub_choice_resolution(system, entry, character)
      Map.has_key?(entry, :options) -> track_selection_resolution(system, entry, character)
      true -> track_value_resolution(entry, character)
    end
  end

  defp track_sub_choice_resolution(system, entry, character) do
    selection = Enum.random(entry.options)

    decision = %{
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

  defp track_selection_resolution(system, entry, character) do
    selection = Enum.random(entry.options)
    n = count_progression_decisions(character.decisions, entry.id) + 1

    decision = %{
      scope: {"character_progression", entry.id},
      choice: "choice_#{n}",
      selection: selection
    }

    updated = %{character | decisions: character.decisions ++ [decision]}
    meta = system.concept_metadata[{"character_progression", entry.id}]

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

  defp track_value_resolution(entry, character) do
    {method, value} = random_value_method(entry.roll)
    n = count_progression_decisions(character.decisions, entry.id) + 1
    [node_key | _] = Expression.extract_refs(entry.effect_target)

    decision = %{
      scope: {"character_progression", entry.id},
      choice: "choice_#{n}",
      selection: method
    }

    effect = %{target: node_key, value: value}

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

  defp random_value_method(die_str) do
    sides = die_str |> String.trim_leading("d") |> String.to_integer()
    average = div(sides, 2) + 1

    if :rand.uniform(2) == 1 do
      {"rolled", Dice.roll("1#{die_str}") |> Enum.sum()}
    else
      {"average", average}
    end
  end

  @doc """
  Computes the list of pending selection progression choice slots for a character,
  taking into account the character's current level and decisions already made.

  Each slot carries `progression_id`, `earned_at_level`, and `max_level_cap` —
  the maximum concept level that was available when that slot was unlocked.
  Decisions already made are excluded; the returned list contains only unresolved slots.

  This should be called after any change that affects character level (e.g. an XP award)
  and stored on the character so that `pending_choices/3` can filter spell options to the
  cap appropriate when each slot was earned, rather than using the current level's cap for
  all pending slots.

  Only applies to progressions whose filter includes `max_level_node`. Progressions with a
  fixed level filter (e.g. cantrips, filtered by `level = 0`) are unaffected.
  """
  def compute_pending_choice_slots(%LoadedSystem{} = system, %Character{} = character) do
    with level_node when not is_nil(level_node) <- system.module.level_node,
         [level_node_key | _] <- Expression.extract_refs(level_node) do
      all_effects = active_effects(system, character)
      resolved = Evaluator.evaluate!(system, character.generated_values, all_effects)
      current_level = trunc(resolved[level_node_key] || 1)

      thresholds = level_xp_thresholds(system)
      xp_target = xp_effect_target(system)

      selection_progressions =
        Enum.filter(system.concept_metadata, fn {{type, _id}, meta} ->
          type == "character_progression" and
            Map.has_key?(meta, "type") and
            get_in(meta, ["filter", "max_level_node"]) != nil
        end)

      level_resolved =
        Map.new(1..current_level, fn level ->
          {level, evaluate_at_level(system, character, level, thresholds, xp_target, all_effects)}
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
        type == "character_progression" and Map.has_key?(meta, "type")
      end)
      |> Map.new(fn {{_type, id}, meta} -> {id, meta["type"]} end)

    selection_counts =
      decisions
      |> Enum.filter(fn d ->
        case d.scope do
          {"character_progression", prog_id} -> Map.has_key?(progression_type_map, prog_id)
          _ -> false
        end
      end)
      |> Enum.reduce(%{}, fn d, acc ->
        {"character_progression", prog_id} = d.scope
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
        |> Enum.filter(fn d -> d.scope == {"character_progression", id} end)
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

  @doc """
  Overrides the `max_level_node` binding in `resolved` with `cap` so that
  `concept_options/4` filters against the given cap rather than the current
  character level.

  Used when a `pending_choice_slots` entry carries a `max_level_cap` that
  reflects the spell level access available when the slot was earned, rather
  than the level at which the choice is ultimately made.

  Returns `resolved` unchanged when `cap` is `nil`.
  """
  def apply_slot_cap(resolved, _meta, nil), do: resolved

  def apply_slot_cap(resolved, meta, cap) do
    max_level_node = get_in(meta, ["filter", "max_level_node"])

    case max_level_node && Expression.extract_refs(max_level_node) do
      [node_key | _] -> Map.put(resolved, node_key, cap)
      _ -> resolved
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
      %{scope: {"character_progression", ^progression_id}} -> true
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

  defp effects_from_decisions(decisions, concept_metadata) do
    Enum.flat_map(decisions, fn
      %{scope: {type, id}, choice: choice_id, selection: selected} ->
        choice_def =
          concept_metadata
          |> Map.get({type, id}, %{})
          |> Map.get("choices", %{})
          |> Map.get(choice_id, %{})

        case choice_def do
          %{
            "contributes_field" => field,
            "contributes_value" => value,
            "type" => target_type
          } ->
            [%{source: {type, id}, target: {target_type, selected, field}, value: value}]

          _ ->
            []
        end

      _ ->
        []
    end)
  end

  defp inventory_effects(%LoadedSystem{} = system, inventory) do
    Enum.flat_map(inventory, fn %InventoryItem{} = item ->
      system.effects
      |> Enum.filter(fn
        %{source: {type, id}} -> type == item.concept_type and id == item.concept_id
        _ -> false
      end)
      |> Enum.map(&Map.put(&1, :item_fields, item.fields))
    end)
  end

  @doc """
  Returns the IDs of root (non-sub) concepts of `type_id` from `concept_metadata`.

  A concept is considered a sub-concept if its ID appears in the `options` list of
  another concept's choice whose `type` matches `type_id` — for example, subclasses
  like `"berserker"` appear in `barbarian`'s `choices.subclass.options`, so they are
  excluded. Only the top-level selectable concepts (e.g. `"barbarian"`, `"wizard"`)
  are returned.
  """
  def root_concept_ids(concept_metadata, type_id) do
    all_ids =
      concept_metadata
      |> Enum.filter(fn {{t, _}, _} -> t == type_id end)
      |> Enum.map(fn {{_, id}, _} -> id end)

    sub_ids =
      concept_metadata
      |> Enum.flat_map(fn {_, meta} -> sub_option_ids(meta, type_id) end)
      |> MapSet.new()

    Enum.reject(all_ids, &MapSet.member?(sub_ids, &1))
  end

  defp random_sub_decisions(concept_metadata, {type_id, concept_id} = key) do
    concept_metadata
    |> Map.get(key, %{})
    |> Map.get("choices", %{})
    |> Enum.flat_map(fn {choice_id, choice_def} ->
      sub_type = choice_def["type"]
      selected = Enum.random(choice_def["options"])
      decision = %{scope: {type_id, concept_id}, choice: choice_id, selection: selected}

      if Map.get(choice_def, "grants_to") == "inventory" do
        [decision]
      else
        [decision | random_sub_decisions(concept_metadata, {sub_type, selected})]
      end
    end)
  end

  defp sub_option_ids(meta, type_id) do
    meta
    |> Map.get("choices", %{})
    |> Enum.flat_map(fn {_, choice_def} ->
      if choice_def["type"] == type_id, do: choice_def["options"] || [], else: []
    end)
  end

  defp collect_active_concepts({_type, _id} = key, decisions, concept_metadata, acc) do
    acc = MapSet.put(acc, key)
    choices = concept_metadata |> Map.get(key, %{}) |> Map.get("choices", %{})

    Enum.reduce(choices, acc, fn {choice_id, choice_def}, acc ->
      decision = Enum.find(decisions, &(&1.scope == key and &1.choice == choice_id))

      if decision && choice_def["grants_to"] != "inventory" do
        collect_active_concepts(
          {choice_def["type"], decision.selection},
          decisions,
          concept_metadata,
          acc
        )
      else
        acc
      end
    end)
  end

  defp level_xp_thresholds(%LoadedSystem{} = system) do
    with level_node when not is_nil(level_node) <- system.module.level_node,
         [{type_id, concept_id, field_name} | _] <- Expression.extract_refs(level_node),
         %{type: :mapping, steps: steps} when not is_nil(steps) <-
           Map.get(system.nodes, {type_id, concept_id, field_name}) do
      Map.new(steps, fn [threshold, level] -> {level, threshold} end)
    else
      _ -> %{}
    end
  end

  defp xp_effect_target(%LoadedSystem{} = system) do
    with level_node when not is_nil(level_node) <- system.module.level_node,
         [{type_id, concept_id, field_name} | _] <- Expression.extract_refs(level_node),
         %{type: :mapping, input: input} when not is_nil(input) <-
           Map.get(system.nodes, {type_id, concept_id, field_name}),
         [node_key | _] <- Expression.extract_refs(input) do
      node_key
    else
      _ -> nil
    end
  end

  defp evaluate_at_level(
         %LoadedSystem{} = system,
         %Character{} = character,
         level,
         thresholds,
         xp_target,
         all_effects
       ) do
    xp_for_level = Map.get(thresholds, level, 0)
    non_xp_effects = Enum.reject(all_effects, &(&1.target == xp_target))

    level_effects =
      if xp_target && xp_for_level > 0 do
        [%{target: xp_target, value: xp_for_level} | non_xp_effects]
      else
        non_xp_effects
      end

    Evaluator.evaluate!(system, character.generated_values, level_effects)
  end
end
