defmodule ExTTRPGDev.Characters do
  @moduledoc """
  This module handles handles character operations
  """
  alias DiceLib.Basic, as: Dice
  alias ExTTRPGDev.Characters.Advancement
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Decision
  alias ExTTRPGDev.Characters.Effects
  alias ExTTRPGDev.Characters.InventoryItem
  alias ExTTRPGDev.Characters.Leveling
  alias ExTTRPGDev.Characters.Store
  alias ExTTRPGDev.RuleSystem.Expression
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystem.InventoryRules
  alias ExTTRPGDev.RuleSystem.Vocabulary
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  # Bound to attributes for use in pattern-match positions; the names are
  # owned by ExTTRPGDev.RuleSystem.Vocabulary.
  @progression_type Vocabulary.progression_type()
  @roll_type Vocabulary.roll_type()

  @doc """
  Get the file path for a character

  ## Examples

      iex> Characters.character_file_path!(%Character{metadata: %Characters.Metadata{slug: "mr_whiskers"}})
      "mr_whiskers.json"
  """
  defdelegate character_file_path!(character), to: Store

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
  defdelegate character_exists?(character), to: Store

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
  defdelegate save_character!(character, overwrite \\ false), to: Store

  @doc """
  Delete a saved character by slug.

  Returns `:ok` if the character was deleted, `{:error, :not_found}` if no
  character with that slug exists.
  """
  defdelegate delete_character(character_slug), to: Store

  @doc """
  List saved characters

  ## Example

      iex> Characters.list_characters!()
      [%Character{}, %Character{}, ...]
  """
  defdelegate list_characters!(), to: Store

  @doc """
  Load a saved character

  ## Example

      iex> Character.load_character!("misu_park_the_cat")
      %Character{}
  """
  defdelegate load_character!(character_slug), to: Store

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
      decision = %Decision{scope: nil, choice: type_id, selection: selected_id}
      [decision | random_sub_decisions(system.concept_metadata, {type_id, selected_id})]
    end)
  end

  @doc """
  Returns the XP needed for a character to reach the next level in the given system.

  Returns `{:ok, xp_needed, next_level}` when a next level exists, or `{:error, :max_level}`
  if the character is already at the highest level defined by the system.

  Returns `{:error, :no_level_thresholds}` if the system does not define a level mapping.
  """
  defdelegate xp_to_next_level(system, character), to: Leveling

  @doc """
  Applies an award concept to a character.

  Awards are concepts of the reserved `award` type whose metadata declares a
  `value_type` (how the awarded value is obtained) and an `effect_target`
  (the node the value contributes to). Supported value types:

  - `"integer"` — the caller must supply an integer `value`
  - `"next_level_xp"` — with `value` as `nil`, the library computes the XP
    needed to reach the character's next level; an explicit `value` takes
    precedence

  Returns `{:ok, updated_character, awarded_value}` where the updated character
  carries the new effect and freshly recomputed `pending_choice_slots` (an
  award may change the character's level and thereby unlock choice slots).

  Error reasons:

  - `{:unknown_award, award_id}`
  - `{:value_required, value_type}` — the award cannot compute its own value
  - `:value_must_be_integer`
  - `{:unsupported_value_type, value_type}`
  - `:max_level` / `:no_level_thresholds` — from `xp_to_next_level/2`
  - `:missing_effect_target` / `{:invalid_effect_target, target}`
  """
  def apply_award(system, character, award_id, value \\ nil),
    do: Advancement.apply_award(system, character, award_id, value)

  @doc """
  Resolves a pending progression choice for a character.

  For selection progressions (metadata declares `type`), `selection` must be
  one of the currently valid options as computed by `pending_choices/3` —
  already-selected concepts are excluded and slot-level caps applied. The
  progression's pending choice slot (if any) is consumed, and the selected
  concept is added to the character's typed inventory when its concept type
  is configured as one (see `add_to_typed_inventory/4`).

  For value progressions (no `type`), `selection` is a free-form method label
  recorded on the decision (e.g. `"rolled"` or `"average"`) and `value` must
  be an integer contributed to the progression's `effect_target`. Value
  progressions are not validated against pending state; callers that need
  that bookkeeping drive them from `pending_choices/3` themselves.

  Returns `{:ok, updated_character}` or `{:error, reason}`:

  - `{:unknown_progression, progression_id}`
  - `{:no_pending_choice, progression_id}` — selection progression with nothing pending
  - `{:invalid_selection, selection}`
  - `:value_required` / `:value_must_be_integer`
  - `:missing_effect_target` / `{:invalid_effect_target, target}`
  - `{:inventory_error, reason}` — from `add_to_typed_inventory/4`
  """
  def resolve_progression_choice(system, character, progression_id, selection, value \\ nil),
    do:
      Advancement.resolve_progression_choice(system, character, progression_id, selection, value)

  @doc """
  Fetches the definition map of the sub-choice `choice_id` declared by the
  concept at `scope` (`{concept_type, concept_id}`).

  Raises if the concept declares no such choice.
  """
  def fetch_choice_def!(system, scope, choice_id),
    do: Advancement.fetch_choice_def!(system, scope, choice_id)

  @doc """
  Returns the currently valid selections for a concept sub-choice: the
  choice's options (see `sub_choice_options/2`) minus selections already made
  for same-type choices under the same scope (siblings share an exclusion
  pool — two skill-proficiency choices cannot both pick the same skill).
  """
  def valid_sub_choices(system, scope, choice_def, decisions),
    do: Advancement.valid_sub_choices(system, scope, choice_def, decisions)

  @doc """
  The raw option list for a sub-choice definition: its declared `options`
  list, or every concept of the choice's `type` when none is declared.
  """
  def sub_choice_options(system, choice_def),
    do: Advancement.sub_choice_options(system, choice_def)

  @doc """
  Returns the current preparation state for the given inventory type.

  Computes mode, cap, eligible pool, always-prepared items, and currently
  prepared items for the character's class. Returns `{:ok, %{mode: nil}}`
  when no class with preparation config is active for this character.
  """
  def preparation_state(%LoadedSystem{} = system, %Character{} = character, type_id) do
    case InventoryRules.type_config(system.inventory_rules, type_id) do
      nil -> {:error, {:unknown_inventory_type, type_id}}
      %{preparation: nil} -> {:error, {:not_a_preparation_type, type_id}}
      config -> do_preparation_state(system, character, type_id, config)
    end
  end

  defp do_preparation_state(system, character, type_id, %{preparation: prep, activation_field: af}) do
    case prep_class_and_mode(system, character, prep) do
      {:error, :no_preparation_class} ->
        {:ok, %{mode: nil}}

      {:ok, class_key, mode} ->
        ctx = prep_context(system, character, class_key, %{type_id: type_id, prep: prep})
        opts = %{prep: prep, af: af, type_id: type_id, mode: mode}
        {:ok, build_prep_state_map(system, character, ctx, opts)}
    end
  end

  # Stage 1 of the shared preparation pipeline: the active class and its
  # preparation mode. Cheap — no DAG evaluation — so activate can reject a
  # wrong mode before any evaluation happens.
  defp prep_class_and_mode(system, character, prep) do
    with {:ok, class_key} <- find_prep_class_for_activate(character, system, prep) do
      {:ok, class_key, get_in(system.concept_metadata, [class_key, prep.mode_field])}
    end
  end

  # Stage 2: everything else both the read path (preparation_state) and the
  # write path (activate) derive — resolved cap, max prepared level, pool
  # config, and the eligible pool. Fallible steps (cap, pool_config) are
  # kept as tagged results so activate can pattern-match errors strictly
  # while preparation_state degrades tolerantly.
  defp prep_context(system, character, {class_type, class_id} = class_key, opts) do
    %{type_id: type_id, prep: prep} = opts
    {_effects, resolved} = resolved_state(system, character)
    max_level = trunc(resolved[prep.max_level_node] || 0)
    pool_name = get_in(system.concept_metadata, [class_key, prep.pool_field])
    pool_config = fetch_pool_config(prep, pool_name)

    eligible_ctx = %{
      type_id: type_id,
      class_id: class_id,
      max_level: max_level,
      level_field: prep.level_field
    }

    eligible =
      case pool_config do
        {:ok, pc} -> compute_eligible_pool(system, character, pc, eligible_ctx)
        {:error, _} -> []
      end

    %{
      cap: resolve_activation_cap(resolved, class_type, class_id, prep),
      max_level: max_level,
      pool_config: pool_config,
      eligible: eligible
    }
  end

  defp build_prep_state_map(system, character, ctx, opts) do
    %{prep: prep, af: af, type_id: type_id, mode: mode} = opts

    cap =
      case ctx.cap do
        {:ok, c} -> c
        {:error, _} -> nil
      end

    always =
      prep_always_prepared(system, character, %{
        prep: prep,
        max_level: ctx.max_level,
        type_id: type_id
      })

    prepared =
      character.inventory
      |> Enum.filter(&(&1.concept_type == type_id and &1.fields[af] == true))
      |> Enum.map(& &1.concept_id)

    %{
      mode: mode,
      cap: cap,
      eligible: ctx.eligible,
      always_prepared: always,
      prepared: prepared
    }
  end

  defp prep_always_prepared(system, character, ctx) do
    %{prep: prep, max_level: max_level, type_id: type_id} = ctx

    with key when not is_nil(key) <- prep.always_prepared_metadata_key,
         true <- max_level > 0 do
      level_ctx = %{type_id: type_id, level_field: prep.level_field, max_level: max_level}
      active = active_concepts(character.decisions, system.concept_metadata)

      active
      |> Enum.flat_map(fn {concept_type, concept_id} ->
        meta = Map.get(system.concept_metadata, {concept_type, concept_id}, %{})
        Map.get(meta, key, [])
      end)
      |> filter_within_level(system.concept_metadata, level_ctx)
    else
      _ -> []
    end
  end

  defp filter_within_level(ids, concept_metadata, ctx) do
    Enum.filter(ids, fn id ->
      meta = Map.get(concept_metadata, {ctx.type_id, id}, %{})
      Map.get(meta, ctx.level_field, 0) <= ctx.max_level
    end)
  end

  @doc """
  Activates or prepares items of the given inventory type for a character.

  For preparation-managed types (e.g. spell): validates `item_ids` against the
  eligible pool and preparation cap, then updates the character's inventory to
  reflect the new prepared state. Items not in `item_ids` are deactivated or
  removed depending on the pool's management strategy.

  Returns `{:ok, updated_character}` or `{:error, reason}`.
  """
  def activate(%LoadedSystem{} = system, %Character{} = character, type_id, item_ids) do
    case InventoryRules.type_config(system.inventory_rules, type_id) do
      nil ->
        {:error, {:unknown_inventory_type, type_id}}

      %{preparation: nil} ->
        {:error, {:not_a_preparation_type, type_id}}

      %{preparation: prep, activation_field: activation_field} ->
        with {:ok, class_key, mode} <- prep_class_and_mode(system, character, prep),
             :ok <- require_prepared_mode_for_activate(mode, prep.activation_mode),
             ctx = prep_context(system, character, class_key, %{type_id: type_id, prep: prep}),
             {:ok, cap} <- ctx.cap,
             {:ok, pool_config} <- ctx.pool_config,
             item_ids = Enum.uniq(item_ids),
             :ok <- validate_eligible_items(item_ids, ctx.eligible),
             :ok <- validate_cap_limit(item_ids, cap) do
          apply_activation(
            character,
            type_id,
            item_ids,
            system.inventory_rules,
            activation_field,
            pool_config,
            ctx.eligible
          )
        end
    end
  end

  @doc """
  Adds a concept to the appropriate typed inventory when a qualifying character
  progression is resolved.

  Looks up the inventory type that lists `progression_id` in `add_on_progression`.
  If none matches, returns `{:ok, character}` unchanged.

  The initial activation value is determined by:
  1. Per-progression `auto_activate` flag (e.g. cantrips — always `true`)
  2. The `auto_activate_when` class condition (e.g. Bard `preparation_mode: "all"`)
  3. Default: `false`

  Returns `{:ok, updated_character}` or `{:error, reason}`.
  """
  def add_to_typed_inventory(
        %LoadedSystem{} = system,
        %Character{} = character,
        progression_id,
        concept_id
      ) do
    case InventoryRules.type_for_progression(system.inventory_rules, progression_id) do
      nil ->
        {:ok, character}

      {type_id, prog_config} ->
        type_config = InventoryRules.type_config(system.inventory_rules, type_id)
        activated = resolve_auto_activate(system, character, prog_config, type_config)

        initial_fields =
          if activated and type_config.activation_field,
            do: %{type_config.activation_field => true},
            else: %{}

        case InventoryItem.new(type_id, concept_id, system.inventory_rules, initial_fields) do
          {:ok, item} -> {:ok, %{character | inventory: character.inventory ++ [item]}}
          error -> error
        end
    end
  end

  @doc """
  Returns the set of active `{type_id, concept_id}` pairs derived from a character's decisions.

  Walks the decisions tree starting from root decisions (scope: nil), adding each selected
  concept and recursing into any sub-choices that concept declares.
  """
  defdelegate active_concepts(decisions, concept_metadata), to: Effects

  @doc """
  Returns the combined effects list for a character against a system.

  Filters system-defined effects to only those whose source concept is active
  (per the character's decisions), then appends the character's own effects.
  """
  defdelegate active_effects(system, character), to: Effects

  @doc """
  Computes the character's active effects and evaluates the full system DAG against them.

  Returns `{effects, resolved}` where `effects` is the output of `active_effects/2` and
  `resolved` is the node-value map from `Evaluator.evaluate!/3`. This is the canonical
  way to obtain a character's resolved state; callers that need only one element can
  discard the other.
  """
  defdelegate resolved_state(system, character), to: Effects

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
        type == @roll_type and meta["target_type"] == type_id
      end)

    unless roll_def do
      raise "No roll defined for concept type \"#{type_id}\" in system \"#{system.module.slug}\""
    end

    {_key, %{"dice" => dice_str, "bonus_field" => bonus_field}} = roll_def

    {_effects, resolved} = resolved_state(system, character)

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
    {resolved, _resolutions} =
      resolve_all(system, character, &resolvable_at_level_1?/1, &rolled_value_method/1, [])

    resolved
  end

  defp resolvable_at_level_1?(%{type: :pending, options: [], earned_at_level: level})
       when level in [nil, 1],
       do: false

  defp resolvable_at_level_1?(%{type: :pending, earned_at_level: level})
       when level in [nil, 1],
       do: true

  defp resolvable_at_level_1?(_), do: false

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
    resolve_all(system, character, &resolvable?/1, &random_value_method/1, [])
  end

  defp resolve_all(
         %LoadedSystem{} = system,
         %Character{} = character,
         resolvable?,
         value_method,
         acc
       ) do
    {_effects, resolved} = resolved_state(system, character)
    choices = pending_choices(system, character, resolved)

    case Enum.find(choices, resolvable?) do
      nil ->
        {character, Enum.reverse(acc)}

      entry ->
        {updated, resolution} = apply_resolution(system, entry, character, value_method)
        resolve_all(system, updated, resolvable?, value_method, [resolution | acc])
    end
  end

  defp resolvable?(%{type: :pending, options: [_ | _]}), do: true
  defp resolvable?(%{type: :pending, options: []}), do: false
  defp resolvable?(%{type: :pending, roll: roll}) when is_binary(roll), do: true
  defp resolvable?(_), do: false

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
    decision = next_progression_decision(character.decisions, entry.id, selection)
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

    decision = next_progression_decision(character.decisions, entry.id, method)
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
      {all_effects, resolved} = resolved_state(system, character)
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

  @doc """
  The single constructor for progression decisions: computes the next 1-based
  choice number from the decisions already made and builds the canonical
  decision map for `progression_id`.
  """
  def next_progression_decision(decisions, progression_id, selection) do
    n = count_progression_decisions(decisions, progression_id) + 1

    %Decision{
      scope: Vocabulary.progression_scope(progression_id),
      choice: Vocabulary.progression_choice_id(n),
      selection: selection
    }
  end

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
      decision = %Decision{scope: {type_id, concept_id}, choice: choice_id, selection: selected}

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

  # --- activate/4 helpers ---

  defp find_prep_class_for_activate(character, system, prep) do
    result =
      Enum.find_value(system.module.character_building_choices, fn %{concept_type: type_id} ->
        find_prep_concept(character.decisions, system.concept_metadata, type_id, prep.mode_field)
      end)

    if result, do: {:ok, result}, else: {:error, :no_preparation_class}
  end

  defp find_prep_concept(decisions, concept_metadata, type_id, mode_field) do
    Enum.find_value(decisions, fn
      %Decision{scope: nil, choice: ^type_id, selection: concept_id} ->
        meta = Map.get(concept_metadata, {type_id, concept_id}, %{})
        if Map.has_key?(meta, mode_field), do: {type_id, concept_id}, else: nil

      _ ->
        nil
    end)
  end

  defp require_prepared_mode_for_activate(mode, mode), do: :ok
  defp require_prepared_mode_for_activate(mode, _), do: {:error, {:mode_not_prepared, mode}}

  defp resolve_activation_cap(resolved, class_type, class_id, prep) do
    case Map.fetch(resolved, {class_type, class_id, prep.cap_field}) do
      {:ok, val} -> {:ok, max(1, trunc(val))}
      :error -> {:error, :no_preparation_cap}
    end
  end

  defp fetch_pool_config(prep, pool_name) when is_binary(pool_name) do
    case Map.fetch(prep.pools, pool_name) do
      {:ok, config} -> {:ok, config}
      :error -> {:error, {:unknown_pool, pool_name}}
    end
  end

  defp fetch_pool_config(_prep, _), do: {:error, :no_pool_configured}

  # ctx: %{type_id, class_id, max_level, level_field}
  defp compute_eligible_pool(system, character, pool_config, ctx) when ctx.max_level > 0 do
    case pool_config.management do
      :add_remove ->
        add_remove_eligible(system.concept_metadata, pool_config, ctx)

      :toggle_field ->
        toggle_field_eligible(character.decisions, system.concept_metadata, pool_config, ctx)
    end
  end

  defp compute_eligible_pool(_system, _character, _pool_config, _ctx), do: []

  defp add_remove_eligible(concept_metadata, pool_config, ctx) do
    %{type_id: type_id, class_id: class_id, max_level: max_level, level_field: level_field} = ctx
    filter_field = pool_config.class_filter_field

    concept_metadata
    |> Enum.filter(fn {{type, _id}, meta} ->
      type == type_id and meta[level_field] in 1..max_level and
        class_id in (meta[filter_field] || [])
    end)
    |> Enum.map(fn {{_type, id}, _} -> id end)
  end

  defp toggle_field_eligible(decisions, concept_metadata, pool_config, ctx) do
    %{type_id: type_id, max_level: max_level, level_field: level_field} = ctx
    scope = {pool_config.scope_type, pool_config.scope_id}
    spellbook_ids = decisions |> Enum.filter(&(&1.scope == scope)) |> MapSet.new(& &1.selection)

    concept_metadata
    |> Enum.filter(fn {{type, id}, meta} ->
      type == type_id and meta[level_field] in 1..max_level and MapSet.member?(spellbook_ids, id)
    end)
    |> Enum.map(fn {{_type, id}, _} -> id end)
  end

  defp validate_eligible_items(item_ids, eligible) do
    eligible_set = MapSet.new(eligible)
    invalid = Enum.reject(item_ids, &MapSet.member?(eligible_set, &1))
    if Enum.empty?(invalid), do: :ok, else: {:error, {:ineligible_items, invalid}}
  end

  defp validate_cap_limit(item_ids, cap) do
    if length(item_ids) <= cap,
      do: :ok,
      else: {:error, {:exceeds_cap, length(item_ids), cap}}
  end

  defp apply_activation(
         character,
         type_id,
         item_ids,
         inv_rules,
         activation_field,
         %{
           management: :add_remove
         },
         eligible
       ) do
    eligible_set = MapSet.new(eligible)

    other_items =
      Enum.reject(character.inventory, fn item ->
        item.concept_type == type_id and MapSet.member?(eligible_set, item.concept_id)
      end)

    result =
      Enum.reduce_while(item_ids, {:ok, []}, fn id, {:ok, acc} ->
        case InventoryItem.new(type_id, id, inv_rules, %{activation_field => true}) do
          {:ok, item} -> {:cont, {:ok, [item | acc]}}
          error -> {:halt, error}
        end
      end)

    case result do
      {:ok, new_items} -> {:ok, %{character | inventory: other_items ++ Enum.reverse(new_items)}}
      error -> error
    end
  end

  defp apply_activation(
         character,
         type_id,
         item_ids,
         _inv_rules,
         activation_field,
         %{
           management: :toggle_field
         },
         eligible
       ) do
    prepared_set = MapSet.new(item_ids)
    eligible_set = MapSet.new(eligible)

    updated_inventory =
      Enum.map(character.inventory, fn item ->
        if item.concept_type == type_id and MapSet.member?(eligible_set, item.concept_id) do
          %{
            item
            | fields:
                Map.put(
                  item.fields,
                  activation_field,
                  MapSet.member?(prepared_set, item.concept_id)
                )
          }
        else
          item
        end
      end)

    {:ok, %{character | inventory: updated_inventory}}
  end

  # --- add_to_typed_inventory/4 helpers ---

  defp resolve_auto_activate(_system, _character, %{auto_activate: true}, _type_config), do: true

  defp resolve_auto_activate(system, character, %{auto_activate: false}, type_config) do
    case type_config && type_config.preparation do
      %{auto_activate_when_field: field, auto_activate_when_value: value}
      when not is_nil(field) ->
        auto_activate_when_met?(system, character, field, value)

      _ ->
        false
    end
  end

  defp auto_activate_when_met?(system, character, field, expected_value) do
    choices = if system.module, do: system.module.character_building_choices, else: []

    Enum.any?(choices, fn %{concept_type: class_type} ->
      Enum.any?(character.decisions, fn
        %Decision{scope: nil, choice: ^class_type, selection: class_id} ->
          meta = Map.get(system.concept_metadata, {class_type, class_id}, %{})
          meta[field] == expected_value

        _ ->
          false
      end)
    end)
  end
end
