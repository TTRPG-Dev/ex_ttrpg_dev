defmodule ExTTRPGDev.CLI.Server do
  @moduledoc """
  JSON server mode for inter-process communication.

  Reads newline-delimited JSON commands from stdin, writes newline-delimited JSON
  responses to stdout. Intended to be driven by the Rust CLI frontend.

  Launched via `ttrpg-dev-engine --server`.

  ## Protocol

  Each request is a single line of JSON:

      {"command": "roll", "dice": "3d6"}
      {"command": "systems.list"}
      {"command": "systems.show", "system": "dnd_5e_srd"}
      {"command": "systems.show", "system": "dnd_5e_srd", "concept_type": "skill"}
      {"command": "characters.gen", "system": "dnd_5e_srd"}
      {"command": "characters.save", "temp_id": "1"}
      {"command": "characters.list"}
      {"command": "characters.list", "system": "dnd_5e_srd"}
      {"command": "characters.show", "character": "thorin-stoneback"}
      {"command": "characters.roll", "character": "thorin-stoneback", "type": "skill", "concept": "acrobatics"}
      {"command": "characters.award", "character": "thorin-stoneback", "award": "experience_points", "value": 300}
      {"command": "characters.award", "character": "thorin-stoneback", "award": "level_up"}
      {"command": "characters.choices", "character": "thorin-stoneback"}
      {"command": "characters.resolve_choice", "character": "thorin-stoneback", "progression": "hp_per_level", "value": 7, "selection": "rolled"}
      {"command": "characters.resolve_choice", "character": "thorin-stoneback", "scope_type": "feat", "scope_id": "ability_score_improvement", "choice": "asi_point_1", "selection": "strength"}
      {"command": "characters.inventory", "character": "thorin-stoneback"}
      {"command": "characters.inventory.add", "character": "thorin-stoneback", "type": "equipment", "id": "longsword"}
      {"command": "characters.inventory.add", "character": "thorin-stoneback", "type": "equipment", "id": "chain_mail", "fields": {"equipped": true}}
      {"command": "characters.inventory.set", "character": "thorin-stoneback", "index": 0, "field": "equipped", "value": true}
      {"command": "characters.spells", "character": "thorin-stoneback"}
      {"command": "characters.activate", "character": "thorin-stoneback", "verb": "prepare", "items": ["bless", "cure_wounds"]}
      {"command": "characters.activate", "character": "thorin-stoneback", "verb": "equip", "items": [0]}

  Each response is a single line of JSON:

      {"status": "ok", "data": {...}}
      {"status": "error", "message": "..."}

  Generated-but-unsaved characters are held in memory under a `temp_id` until
  `characters.save` is called or the server exits.
  """

  alias DiceLib.Basic, as: Dice
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, InventoryItem}
  alias ExTTRPGDev.CLI.Serializer
  alias ExTTRPGDev.RuleSystem.{Evaluator, InventoryRules}
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @type state :: %{pending: %{String.t() => Character.t()}, next_id: non_neg_integer()}

  def run do
    loop(%{pending: %{}, next_id: 1})
  end

  @doc false
  def handle_command(msg, state), do: handle(msg, state)

  defp loop(state) do
    case IO.gets("") do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line when is_binary(line) ->
        {response, new_state} =
          line
          |> String.trim()
          |> dispatch(state)

        IO.puts(Poison.encode!(response))
        loop(new_state)
    end
  end

  defp dispatch("", state), do: {ok(%{}), state}

  defp dispatch(line, state) do
    case Poison.decode(line) do
      {:ok, cmd} -> handle(cmd, state)
      {:error, _} -> {error("invalid JSON"), state}
    end
  end

  # --- Roll ---

  defp handle(%{"command" => "roll", "dice" => dice_str}, state) do
    specs =
      dice_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    try do
      results =
        specs
        |> Dice.multi_roll!()
        |> Enum.map(fn {spec, rolls} ->
          %{spec: spec, rolls: rolls, total: Enum.sum(rolls)}
        end)

      {ok(%{results: results}), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  # --- Systems ---

  defp handle(%{"command" => "systems.list"}, state) do
    {ok(%{systems: RuleSystems.list_systems()}), state}
  end

  defp handle(%{"command" => "systems.show", "system" => slug} = cmd, state) do
    concept_type = Map.get(cmd, "concept_type")
    concept_id = Map.get(cmd, "concept_id")

    try do
      system = RuleSystems.load_system!(slug)

      data =
        cond do
          concept_id != nil ->
            meta = system.concept_metadata[{concept_type, concept_id}] || %{}
            %{id: concept_id, concept_type: concept_type, fields: meta}

          concept_type != nil ->
            Serializer.serialize_concepts(system, concept_type)

          true ->
            Serializer.serialize_system(system)
        end

      {ok(data), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  # --- Characters ---

  defp handle(%{"command" => "characters.gen", "system" => slug} = msg, state) do
    try do
      system = RuleSystems.load_system!(slug)
      decisions = Characters.random_decisions(system)
      character = Character.gen_character!(system, decisions)
      slots = Characters.compute_pending_choice_slots(system, character)

      character =
        Characters.auto_resolve_pending(system, %{character | pending_choice_slots: slots})

      temp_id = Integer.to_string(state.next_id)

      new_state = %{
        state
        | pending: Map.put(state.pending, temp_id, character),
          next_id: state.next_id + 1
      }

      data =
        Map.put(
          Serializer.serialize_character(system, character, nil, parse_display_mode(msg)),
          :temp_id,
          temp_id
        )

      {ok(data), new_state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  # --- Character Build ---

  defp handle(
         %{"command" => "characters.build_start", "system" => slug, "name" => name},
         state
       ) do
    try do
      system = RuleSystems.load_system!(slug)
      character = Character.gen_character!(system, [])

      slug = slugify_name(name)
      character = %{character | name: name, metadata: %{character.metadata | slug: slug}}
      temp_id = Integer.to_string(state.next_id)
      pending = Map.put(state.pending, temp_id, character)
      new_state = %{state | pending: pending, next_id: state.next_id + 1}

      building_choices = Serializer.serialize_building_choices(system)
      {ok(%{temp_id: temp_id, building_choices: building_choices}), new_state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{
           "command" => "characters.build_select",
           "temp_id" => temp_id,
           "concept_type" => concept_type,
           "concept_id" => concept_id
         },
         state
       ) do
    try do
      character = fetch_pending!(state, temp_id)
      system = RuleSystems.load_system!(character.metadata.rule_system)
      decision = %{scope: nil, choice: concept_type, selection: concept_id}
      updated = %{character | decisions: character.decisions ++ [decision]}

      sub_choices =
        Serializer.serialize_concept_sub_choices(
          concept_type,
          concept_id,
          updated.decisions,
          system
        )

      new_state = %{state | pending: Map.put(state.pending, temp_id, updated)}
      {ok(%{sub_choices: sub_choices}), new_state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{
           "command" => "characters.build_resolve_sub",
           "temp_id" => temp_id,
           "scope_type" => scope_type,
           "scope_id" => scope_id,
           "choice" => choice_id,
           "selection" => selection
         },
         state
       ) do
    try do
      character = fetch_pending!(state, temp_id)
      system = RuleSystems.load_system!(character.metadata.rule_system)
      scope = {scope_type, scope_id}
      choice_def = Serializer.fetch_choice_def!(system, scope, choice_id)
      valid = Serializer.valid_sub_choices(system, scope, choice_def, character.decisions)
      validate_concept_selection!(selection, valid)
      decision = %{scope: scope, choice: choice_id, selection: selection}
      updated = %{character | decisions: character.decisions ++ [decision]}

      sub_choices =
        Serializer.serialize_concept_sub_choices(scope_type, scope_id, updated.decisions, system)

      new_state = %{state | pending: Map.put(state.pending, temp_id, updated)}
      {ok(%{sub_choices: sub_choices}), new_state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(%{"command" => "characters.build_finish", "temp_id" => temp_id} = msg, state) do
    try do
      char = fetch_pending!(state, temp_id)
      sys = RuleSystems.load_system!(char.metadata.rule_system)
      inv = Character.inventory_from_decisions(char.decisions, sys)
      slots = Characters.compute_pending_choice_slots(sys, %{char | inventory: inv})
      updated = %{char | inventory: inv, pending_choice_slots: slots}
      Characters.save_character!(updated)
      new_state = %{state | pending: Map.delete(state.pending, temp_id)}
      resolved = resolve_character(sys, updated)
      choices = Characters.pending_choices(sys, updated, resolved)
      mode = parse_display_mode(msg)
      ser = Serializer.serialize_character(sys, updated, updated.metadata.slug, mode)
      data = Map.put(ser, :pending_choices, Serializer.serialize_choices_list(choices, sys, mode))

      {ok(data), new_state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(%{"command" => "characters.save", "temp_id" => temp_id}, state) do
    case Map.get(state.pending, temp_id) do
      nil ->
        {error("no pending character with temp_id #{inspect(temp_id)}"), state}

      character ->
        try do
          Characters.save_character!(character)
          new_state = %{state | pending: Map.delete(state.pending, temp_id)}
          {ok(%{slug: character.metadata.slug}), new_state}
        rescue
          e -> {error(Exception.message(e)), state}
        end
    end
  end

  defp handle(%{"command" => "characters.list"} = cmd, state) do
    system_filter = Map.get(cmd, "system")

    try do
      characters =
        Characters.list_characters!()
        |> Enum.map(&Characters.load_character!/1)
        |> Enum.filter(fn c ->
          system_filter == nil or c.metadata.rule_system == system_filter
        end)
        |> Enum.map(fn c ->
          %{
            slug: c.metadata.slug,
            name: c.name,
            rule_system: c.metadata.rule_system
          }
        end)

      {ok(%{characters: characters}), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{
           "command" => "characters.award",
           "character" => slug,
           "award" => award_id,
           "value" => value
         } = msg,
         state
       ) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      award_meta =
        system.concept_metadata[{"award", award_id}] ||
          raise("unknown award: #{inspect(award_id)}")

      updated = apply_award!(character, award_meta, value)
      new_slots = Characters.compute_pending_choice_slots(system, updated)
      updated = %{updated | pending_choice_slots: new_slots}
      Characters.save_character!(updated, true)

      resolved = resolve_character(system, updated)
      choices = Characters.pending_choices(system, updated, resolved)

      data =
        Serializer.serialize_character(system, updated, slug, parse_display_mode(msg))
        |> Map.put(
          :pending_choices,
          Serializer.serialize_choices_list(choices, system, parse_display_mode(msg))
        )

      {ok(data), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{"command" => "characters.award", "character" => slug, "award" => award_id} = msg,
         state
       ) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      award_meta =
        system.concept_metadata[{"award", award_id}] ||
          raise("unknown award: #{inspect(award_id)}")

      xp_needed = compute_next_level_xp!(system, character, award_meta)
      updated = apply_award!(character, award_meta, xp_needed)
      new_slots = Characters.compute_pending_choice_slots(system, updated)
      updated = %{updated | pending_choice_slots: new_slots}
      Characters.save_character!(updated, true)

      resolved = resolve_character(system, updated)
      choices = Characters.pending_choices(system, updated, resolved)

      data =
        Serializer.serialize_character(system, updated, slug, parse_display_mode(msg))
        |> Map.put(
          :pending_choices,
          Serializer.serialize_choices_list(choices, system, parse_display_mode(msg))
        )
        |> Map.put(:awarded_xp, xp_needed)

      {ok(data), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(%{"command" => "characters.choices", "character" => slug} = msg, state) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      resolved = resolve_character(system, character)
      choices = Characters.pending_choices(system, character, resolved)

      {ok(%{
         pending_choices:
           Serializer.serialize_choices_list(choices, system, parse_display_mode(msg))
       }), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{
           "command" => "characters.resolve_choice",
           "character" => slug,
           "progression" => progression_id,
           "selection" => selection
         } = msg,
         state
       ) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      meta =
        system.concept_metadata[{"character_progression", progression_id}] ||
          raise("unknown progression: #{inspect(progression_id)}")

      choice_number =
        Enum.count(character.decisions, fn
          %{scope: {"character_progression", ^progression_id}} -> true
          _ -> false
        end) + 1

      decision = %{
        scope: {"character_progression", progression_id},
        choice: "choice_#{choice_number}",
        selection: selection
      }

      updated =
        if Map.has_key?(meta, "type") do
          resolved = resolve_character(system, character)
          active = Characters.active_concepts(character.decisions, system.concept_metadata)

          already_selected =
            character.decisions
            |> Enum.filter(fn d -> d.scope == {"character_progression", progression_id} end)
            |> MapSet.new(& &1.selection)

          capped_resolved = cap_resolved_for_slot(character, progression_id, meta, resolved)

          options =
            Characters.concept_options(meta, system.concept_metadata, active, capped_resolved)
            |> Enum.reject(&MapSet.member?(already_selected, &1))

          validate_concept_selection!(selection, options)

          with_decision = %{
            character
            | decisions: character.decisions ++ [decision],
              pending_choice_slots: consume_slot(character.pending_choice_slots, progression_id)
          }

          apply_inventory_addition!(system, with_decision, progression_id, selection)
        else
          value = Map.fetch!(msg, "value")
          unless is_integer(value), do: raise("value must be an integer")
          parsed_target = load_progression_target!(system, progression_id)

          %{
            character
            | effects: character.effects ++ [%{target: parsed_target, value: value}],
              decisions: character.decisions ++ [decision]
          }
        end

      Characters.save_character!(updated, true)

      resolved = resolve_character(system, updated)
      choices = Characters.pending_choices(system, updated, resolved)

      data =
        Serializer.serialize_character(system, updated, slug, parse_display_mode(msg))
        |> Map.put(
          :pending_choices,
          Serializer.serialize_choices_list(choices, system, parse_display_mode(msg))
        )

      {ok(data), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(%{"command" => "characters.random_resolve", "character" => slug} = msg, state) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)
      slots = Characters.compute_pending_choice_slots(system, character)
      character = %{character | pending_choice_slots: slots}

      {updated, resolutions} = Characters.random_resolve_all(system, character)
      Characters.save_character!(updated, true)

      data =
        Serializer.serialize_character(system, updated, slug, parse_display_mode(msg))
        |> Map.put(:resolutions, Serializer.serialize_resolutions(resolutions, system))

      {ok(data), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(%{"command" => "characters.delete", "character" => slug}, state) do
    case Characters.delete_character(slug) do
      :ok -> {ok(%{deleted: slug}), state}
      {:error, :not_found} -> {error("Character not found: #{slug}"), state}
    end
  end

  defp handle(%{"command" => "characters.show", "character" => slug} = msg, state) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)
      data = Serializer.serialize_character(system, character, slug, parse_display_mode(msg))
      {ok(data), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{
           "command" => "characters.roll",
           "character" => slug,
           "type" => type_id,
           "concept" => concept_id
         },
         state
       ) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)
      result = Characters.concept_roll!(system, character, type_id, concept_id)

      concept_name =
        case Map.get(system.concept_metadata, {type_id, concept_id}) do
          nil -> concept_id
          meta -> meta["name"] || concept_id
        end

      {ok(%{
         concept_name: concept_name,
         dice: result.dice,
         rolls: result.rolls,
         bonus: result.bonus,
         total: result.total
       }), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  # --- Inventory ---

  defp handle(%{"command" => "characters.inventory", "character" => slug}, state) do
    try do
      character = Characters.load_character!(slug)
      {ok(%{inventory: Serializer.serialize_inventory(character.inventory)}), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{
           "command" => "characters.inventory.add",
           "character" => slug,
           "type" => type,
           "id" => id
         } =
           cmd,
         state
       ) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)
      custom_fields = Map.get(cmd, "fields", %{})

      case InventoryItem.new(type, id, system.inventory_rules, custom_fields) do
        {:ok, item} ->
          updated = %{character | inventory: character.inventory ++ [item]}
          Characters.save_character!(updated, true)
          {ok(%{inventory: Serializer.serialize_inventory(updated.inventory)}), state}

        {:error, reason} ->
          {error("cannot add item: #{inspect(reason)}"), state}
      end
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{
           "command" => "characters.inventory.set",
           "character" => slug,
           "index" => index,
           "field" => field,
           "value" => value
         },
         state
       ) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      item =
        Enum.at(character.inventory, index) ||
          raise("no inventory item at index #{inspect(index)}")

      case InventoryItem.set_field(item, field, value, system.inventory_rules) do
        {:ok, updated_item} ->
          new_inventory = List.replace_at(character.inventory, index, updated_item)
          updated = %{character | inventory: new_inventory}
          Characters.save_character!(updated, true)
          {ok(%{inventory: Serializer.serialize_inventory(updated.inventory)}), state}

        {:error, reason} ->
          {error("cannot set field: #{inspect(reason)}"), state}
      end
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{
           "command" => "characters.resolve_choice",
           "character" => slug,
           "scope_type" => scope_type,
           "scope_id" => scope_id,
           "choice" => choice_id,
           "selection" => selection
         } = msg,
         state
       ) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      choice_def =
        get_in(system.concept_metadata, [{scope_type, scope_id}, "choices", choice_id]) ||
          raise("unknown choice #{inspect(choice_id)} on #{scope_type}(#{scope_id})")

      options =
        system.concept_metadata
        |> Enum.filter(fn {{t, _id}, _} -> t == choice_def["type"] end)
        |> Enum.map(fn {{_t, id}, _} -> id end)

      validate_concept_selection!(selection, options)

      decision = %{scope: {scope_type, scope_id}, choice: choice_id, selection: selection}
      updated = %{character | decisions: character.decisions ++ [decision]}
      Characters.save_character!(updated, true)

      resolved = resolve_character(system, updated)
      choices = Characters.pending_choices(system, updated, resolved)

      data =
        Serializer.serialize_character(system, updated, slug, parse_display_mode(msg))
        |> Map.put(
          :pending_choices,
          Serializer.serialize_choices_list(choices, system, parse_display_mode(msg))
        )

      {ok(data), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  # --- Spell preparation ---

  defp handle(%{"command" => "characters.spells", "character" => slug}, state) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      result =
        case InventoryRules.preparation_types(system.inventory_rules) do
          [] ->
            {:ok, %{preparation_mode: nil}}

          [{type_id, _} | _] ->
            case Characters.preparation_state(system, character, type_id) do
              {:ok, %{mode: nil}} -> {:ok, %{preparation_mode: nil}}
              {:ok, s} -> {:ok, format_prep_response(s)}
              error -> error
            end
        end

      case result do
        {:ok, data} -> {ok(data), state}
        {:error, reason} -> {error(inspect(reason)), state}
      end
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{
           "command" => "characters.activate",
           "character" => slug,
           "verb" => verb,
           "items" => item_ids
         },
         state
       ) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      case InventoryRules.type_for_activate_command(system.inventory_rules, verb) do
        nil ->
          {error("unknown activate verb: #{inspect(verb)}"), state}

        {type_id, _config} ->
          case Characters.activate(system, character, type_id, item_ids) do
            {:ok, updated} ->
              Characters.save_character!(updated, true)
              {ok(%{inventory: Serializer.serialize_inventory(updated.inventory)}), state}

            {:error, reason} ->
              {error(format_activate_error(reason)), state}
          end
      end
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(%{"command" => cmd}, state) do
    {error("unknown command: #{inspect(cmd)}"), state}
  end

  defp handle(_, state) do
    {error("request must have a \"command\" field"), state}
  end

  defp format_prep_response(%{
         mode: mode,
         cap: cap,
         eligible: eligible,
         always_prepared: always,
         prepared: prepared
       }) do
    base = %{
      preparation_mode: mode,
      eligible_items: eligible,
      prepared_items: prepared,
      always_active: always
    }

    if cap, do: Map.put(base, :cap, cap), else: base
  end

  defp format_activate_error({:ineligible_items, ids}),
    do: "ineligible items: #{Enum.join(ids, ", ")}"

  defp format_activate_error({:exceeds_cap, count, cap}),
    do: "cannot prepare more than #{cap} (given: #{count})"

  defp format_activate_error({:mode_not_prepared, _}),
    do: "spells for this class are not manually prepared"

  defp format_activate_error(:no_preparation_class),
    do: "no class with preparation_mode found for this character"

  defp format_activate_error(:no_preparation_cap), do: "class has no preparation cap"
  defp format_activate_error(reason), do: inspect(reason)

  defp apply_inventory_addition!(system, character, progression_id, selection) do
    case Characters.add_to_typed_inventory(system, character, progression_id, selection) do
      {:ok, result} -> result
      {:error, reason} -> raise("failed to add to inventory: #{inspect(reason)}")
    end
  end

  defp resolve_character(%LoadedSystem{} = system, %Character{} = character) do
    system
    |> Characters.active_effects(character)
    |> then(&Evaluator.evaluate!(system, character.generated_values, &1))
  end

  defp load_progression_target!(%LoadedSystem{} = system, progression_id) do
    meta =
      system.concept_metadata[{"character_progression", progression_id}] ||
        raise("unknown progression: #{inspect(progression_id)}")

    effect_target = meta["effect_target"] || raise("progression has no effect_target")
    parse_effect_target!(effect_target)
  end

  defp validate_concept_selection!(selection, valid_options) do
    unless selection in valid_options do
      raise("#{inspect(selection)} is not available for this character and progression")
    end
  end

  @effect_target_regex ~r/^(\w+)\('([^']+)'\)\.(\w+)$/

  defp parse_effect_target!(target) do
    case Regex.run(@effect_target_regex, target, capture: :all_but_first) do
      [type_id, concept_id, field] -> {type_id, concept_id, field}
      _ -> raise("invalid effect target: #{inspect(target)}")
    end
  end

  defp cap_resolved_for_slot(character, progression_id, meta, resolved) do
    case Enum.find(character.pending_choice_slots, &(&1.progression_id == progression_id)) do
      %{max_level_cap: cap} -> Characters.apply_slot_cap(resolved, meta, cap)
      nil -> resolved
    end
  end

  defp consume_slot(pending_choice_slots, progression_id) do
    case Enum.split_while(pending_choice_slots, &(&1.progression_id != progression_id)) do
      {before_slots, [_ | after_slots]} -> before_slots ++ after_slots
      _ -> pending_choice_slots
    end
  end

  defp apply_award!(character, %{"value_type" => "integer", "effect_target" => target}, value) do
    unless is_integer(value), do: raise("value must be an integer for this award")
    parsed_target = parse_effect_target!(target)
    %{character | effects: character.effects ++ [%{target: parsed_target, value: value}]}
  end

  defp apply_award!(
         character,
         %{"value_type" => "next_level_xp", "effect_target" => target},
         xp_needed
       ) do
    parsed_target = parse_effect_target!(target)
    %{character | effects: character.effects ++ [%{target: parsed_target, value: xp_needed}]}
  end

  defp apply_award!(_character, %{"value_type" => value_type}, _value) do
    raise("unsupported award value_type: #{inspect(value_type)}")
  end

  defp compute_next_level_xp!(system, character, %{"value_type" => "next_level_xp"}) do
    case Characters.xp_to_next_level(system, character) do
      {:ok, xp_needed, _next_level} -> xp_needed
      {:error, :max_level} -> raise("character is already at max level")
      {:error, :no_level_thresholds} -> raise("system does not define level XP thresholds")
    end
  end

  defp compute_next_level_xp!(_system, _character, %{"value_type" => value_type}) do
    raise(
      "award #{inspect(value_type)} requires an explicit value; use: characters award <slug> #{value_type} <value>"
    )
  end

  defp fetch_pending!(state, temp_id) do
    Map.get(state.pending, temp_id) || raise("no pending character: #{inspect(temp_id)}")
  end

  defp slugify_name(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[!#$%&()*+,.:;<=>?@\^_`'{|}~-]/, "")
    |> String.replace(" ", "_")
  end

  defp parse_display_mode(msg) do
    case Map.get(msg, "display_mode", "default") do
      "verbose" -> :verbose
      "succinct" -> :succinct
      _ -> :default
    end
  end

  # --- Response helpers ---

  defp ok(data), do: %{status: "ok", data: data}
  defp error(message), do: %{status: "error", message: message}
end
