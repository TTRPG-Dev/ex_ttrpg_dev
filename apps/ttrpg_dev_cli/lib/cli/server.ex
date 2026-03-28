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
      {"command": "characters.choices", "character": "thorin-stoneback"}
      {"command": "characters.resolve_choice", "character": "thorin-stoneback", "progression": "hp_per_level", "value": 7, "selection": "rolled"}
      {"command": "characters.inventory", "character": "thorin-stoneback"}
      {"command": "characters.inventory.add", "character": "thorin-stoneback", "type": "equipment", "id": "longsword"}
      {"command": "characters.inventory.add", "character": "thorin-stoneback", "type": "equipment", "id": "chain_mail", "fields": {"equipped": true}}
      {"command": "characters.inventory.set", "character": "thorin-stoneback", "index": 0, "field": "equipped", "value": true}

  Each response is a single line of JSON:

      {"status": "ok", "data": {...}}
      {"status": "error", "message": "..."}

  Generated-but-unsaved characters are held in memory under a `temp_id` until
  `characters.save` is called or the server exits.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, InventoryItem}
  alias ExTTRPGDev.CLI.ConceptDisplay
  alias ExTTRPGDev.Dice
  alias ExTTRPGDev.RuleSystem.{Evaluator, InventoryRules}
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @type state :: %{pending: %{String.t() => Character.t()}, next_id: non_neg_integer()}

  def run do
    loop(%{pending: %{}, next_id: 1})
  end

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

    try do
      system = RuleSystems.load_system!(slug)

      data =
        if concept_type,
          do: serialize_concepts(system, concept_type),
          else: serialize_system(system)

      {ok(data), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  # --- Characters ---

  defp handle(%{"command" => "characters.gen", "system" => slug}, state) do
    try do
      system = RuleSystems.load_system!(slug)
      decisions = Characters.random_decisions(system)
      character = Character.gen_character!(system, decisions)
      temp_id = Integer.to_string(state.next_id)

      new_state = %{
        state
        | pending: Map.put(state.pending, temp_id, character),
          next_id: state.next_id + 1
      }

      data = Map.put(serialize_character(system, character, nil, :default), :temp_id, temp_id)
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
        serialize_character(system, updated, slug, parse_display_mode(msg))
        |> Map.put(
          :pending_choices,
          serialize_choices_list(choices, system, parse_display_mode(msg))
        )

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

      {ok(%{pending_choices: serialize_choices_list(choices, system, parse_display_mode(msg))}),
       state}
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

          %{
            character
            | decisions: character.decisions ++ [decision],
              pending_choice_slots: consume_slot(character.pending_choice_slots, progression_id)
          }
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
        serialize_character(system, updated, slug, parse_display_mode(msg))
        |> Map.put(
          :pending_choices,
          serialize_choices_list(choices, system, parse_display_mode(msg))
        )

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
      data = serialize_character(system, character, slug, parse_display_mode(msg))
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
      {ok(%{inventory: serialize_inventory(character.inventory)}), state}
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
          {ok(%{inventory: serialize_inventory(updated.inventory)}), state}

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
          {ok(%{inventory: serialize_inventory(updated.inventory)}), state}

        {:error, reason} ->
          {error("cannot set field: #{inspect(reason)}"), state}
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

  # --- Serialization ---

  defp serialize_system(%LoadedSystem{module: mod}) do
    %{
      name: mod.name,
      slug: mod.slug,
      version: mod.version,
      publisher: mod.publisher,
      family: mod.family,
      series: mod.series,
      concept_types: Enum.map(mod.concept_types, &%{id: &1.id, name: &1.name})
    }
  end

  defp serialize_concepts(%LoadedSystem{concept_metadata: meta}, concept_type) do
    concepts =
      meta
      |> Enum.filter(fn {{type, _id}, _} -> type == concept_type end)
      |> Enum.sort_by(fn {{_type, id}, _} -> id end)
      |> Enum.map(fn {{_type, id}, fields} ->
        %{id: id, name: Map.get(fields, "name", id)}
      end)

    %{concept_type: concept_type, concepts: concepts}
  end

  defp serialize_character(%LoadedSystem{} = system, %Character{} = character, slug, display_mode) do
    active = Characters.active_concepts(character.decisions, system.concept_metadata)
    resolved = resolve_character(system, character)
    resolved_by_concept = Enum.group_by(resolved, fn {{type, id, _field}, _} -> {type, id} end)
    inventory_ids = MapSet.new(character.inventory, &{&1.concept_type, &1.concept_id})

    %{
      name: character.name,
      rule_system: character.metadata.rule_system,
      slug: slug,
      choices: serialize_choices(system, character),
      character_lists: serialize_character_lists(system, character, active, display_mode),
      concept_types:
        serialize_concept_type_values(system, resolved_by_concept, inventory_ids, active),
      selected_concepts: serialize_selected_concepts(system, character, display_mode)
    }
  end

  defp serialize_selected_concepts(
         %LoadedSystem{} = system,
         %Character{} = character,
         display_mode
       ) do
    selection_progressions =
      system.concept_metadata
      |> Enum.filter(fn {{type, _id}, meta} ->
        type == "character_progression" and Map.has_key?(meta, "type")
      end)
      |> Map.new(fn {{_type, id}, meta} ->
        {id, %{concept_type: meta["type"], name: meta["name"] || id}}
      end)

    character.decisions
    |> Enum.filter(fn
      %{scope: {"character_progression", prog_id}} ->
        Map.has_key?(selection_progressions, prog_id)

      _ ->
        false
    end)
    |> Enum.map(fn %{scope: {"character_progression", prog_id}, selection: selection} ->
      prog = selection_progressions[prog_id]
      {prog.concept_type, prog.name, selection}
    end)
    |> Enum.uniq()
    |> Enum.map(fn {concept_type, progression_name, id} ->
      meta = system.concept_metadata[{concept_type, id}] || %{"name" => id}
      template = find_display_template(system, concept_type)
      label = ConceptDisplay.render(template, meta, display_mode)
      %{progression: progression_name, id: id, label: label}
    end)
    |> Enum.sort_by(fn %{progression: prog, label: label} -> {prog, label} end)
  end

  defp serialize_choices(%LoadedSystem{} = system, %Character{} = character) do
    system.module.character_building_choices
    |> Enum.flat_map(&serialize_choice_entry(system, character, &1))
  end

  defp serialize_choice_entry(system, character, %{concept_type: type_id}) do
    root = Enum.find(character.decisions, &(&1.scope == nil and &1.choice == type_id))

    if root do
      type_name =
        Enum.find_value(system.module.concept_types, &if(&1.id == type_id, do: &1.name))

      chain =
        concept_name_chain(character.decisions, system.concept_metadata, type_id, root.selection)

      [%{type_name: type_name, value: Enum.join(chain, " / ")}]
    else
      []
    end
  end

  defp concept_name_chain(decisions, concept_metadata, type_id, concept_id) do
    name = get_in(concept_metadata, [{type_id, concept_id}, "name"]) || concept_id

    sub_names =
      concept_metadata
      |> Map.get({type_id, concept_id}, %{})
      |> Map.get("choices", %{})
      |> Enum.flat_map(&same_type_sub_chain(decisions, concept_metadata, type_id, concept_id, &1))

    [name | sub_names]
  end

  defp same_type_sub_chain(
         decisions,
         concept_metadata,
         type_id,
         concept_id,
         {choice_id, choice_def}
       ) do
    if choice_def["type"] == type_id do
      decision =
        Enum.find(decisions, &(&1.scope == {type_id, concept_id} and &1.choice == choice_id))

      if decision,
        do: concept_name_chain(decisions, concept_metadata, type_id, decision.selection),
        else: []
    else
      []
    end
  end

  defp serialize_character_lists(system, character, active, display_mode) do
    ctx = {system, display_mode}

    system.module.character_lists
    |> Enum.map(&serialize_character_list_category(&1, ctx, character, active))
    |> Enum.reject(fn %{items: items} -> items == [] end)
  end

  defp serialize_character_list_category(cat, {system, display_mode}, character, active) do
    template = find_display_template(system, cat.concept_type)
    ids = collect_from_active(active, system.concept_metadata, cat.metadata_key)

    items =
      case cat.concept_type do
        nil ->
          ids

        concept_type ->
          Enum.map(ids, fn id ->
            meta = system.concept_metadata[{concept_type, id}] || %{"name" => id}
            ConceptDisplay.render(template, meta, display_mode)
          end)
      end

    choice_template = find_display_template(system, cat.choice_concept_type)

    choice_items =
      case cat.choice_concept_type do
        nil ->
          []

        concept_type ->
          character.decisions
          |> chosen_by_type(system.concept_metadata, concept_type)
          |> Enum.map(fn id ->
            meta = system.concept_metadata[{concept_type, id}] || %{"name" => id}
            ConceptDisplay.render(choice_template, meta, display_mode)
          end)
      end

    %{label: cat.label, items: (items ++ choice_items) |> Enum.uniq() |> Enum.sort()}
  end

  defp collect_from_active(active, concept_metadata, key) do
    active
    |> Enum.flat_map(fn {type, id} ->
      Map.get(concept_metadata[{type, id}] || %{}, key, [])
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp chosen_by_type(decisions, concept_metadata, type) do
    decisions
    |> Enum.filter(fn
      %{scope: {scope_type, scope_id}, choice: choice_id} ->
        choice_def =
          get_in(concept_metadata, [{scope_type, scope_id}, "choices", choice_id]) || %{}

        choice_def["type"] == type and choice_def["grants_to"] != "inventory"

      _ ->
        false
    end)
    |> Enum.map(& &1.selection)
  end

  defp serialize_inventory(inventory) do
    inventory
    |> Enum.with_index()
    |> Enum.map(fn {%InventoryItem{} = item, index} ->
      %{
        index: index,
        concept_type: item.concept_type,
        concept_id: item.concept_id,
        fields: item.fields
      }
    end)
  end

  defp serialize_concept_type_values(
         %LoadedSystem{} = system,
         resolved_by_concept,
         inventory_ids,
         active
       ) do
    choice_types =
      system.module.character_building_choices
      |> Enum.map(& &1.concept_type)
      |> MapSet.new()

    ctx = %{
      concept_metadata: system.concept_metadata,
      inventory_rules: system.inventory_rules,
      inventory_ids: inventory_ids,
      signed: MapSet.new(system.module.display_config.signed_fields),
      choice_types: choice_types,
      active: active
    }

    Enum.flat_map(
      system.module.concept_types,
      &serialize_concept_type(&1, resolved_by_concept, ctx)
    )
  end

  defp serialize_concept_type(concept_type, resolved_by_concept, ctx) do
    inventoriable = InventoryRules.inventoriable?(ctx.inventory_rules, concept_type.id)
    choice_driven = MapSet.member?(ctx.choice_types, concept_type.id)

    concepts =
      ctx.concept_metadata
      |> Enum.filter(fn {{type, _id}, _} -> type == concept_type.id end)
      |> Enum.sort_by(fn {{_type, id}, _} -> id end)
      |> Enum.filter(fn {{type, id}, meta} ->
        Map.has_key?(resolved_by_concept, {type, id}) and
          not Map.get(meta, "hidden", false) and
          (not inventoriable or MapSet.member?(ctx.inventory_ids, {type, id})) and
          (not choice_driven or MapSet.member?(ctx.active, {type, id}))
      end)

    if concepts == [] do
      []
    else
      entries = Enum.map(concepts, &serialize_concept_entry(&1, resolved_by_concept, ctx.signed))
      [%{id: concept_type.id, name: concept_type.name, concepts: entries}]
    end
  end

  defp serialize_concept_entry({{type, id}, meta}, resolved_by_concept, signed) do
    name = meta["name"] || id

    fields =
      resolved_by_concept[{type, id}]
      |> Enum.sort_by(fn {{_t, _i, field}, _} -> field end)
      |> Enum.map(fn {{_t, _i, field}, value} ->
        %{name: field, value: format_field_value(field, value, signed)}
      end)

    %{id: id, name: name, fields: fields}
  end

  defp format_field_value(field, value, signed) when is_integer(value) and value >= 0 do
    if MapSet.member?(signed, field), do: "+#{value}", else: "#{value}"
  end

  defp format_field_value(_field, value, _signed), do: "#{value}"

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

  defp apply_award!(_character, %{"value_type" => value_type}, _value) do
    raise("unsupported award value_type: #{inspect(value_type)}")
  end

  defp serialize_choices_list(choices, system, display_mode) do
    Enum.map(choices, fn
      %{type: :pending, options: options} = c ->
        concept_type =
          get_in(system.concept_metadata, [{"character_progression", c.id}, "type"])

        template = find_display_template(system, concept_type)

        rendered_options =
          Enum.map(options, fn id ->
            fields = system.concept_metadata[{concept_type, id}] || %{"name" => id}
            %{id: id, label: ConceptDisplay.render(template, fields, display_mode)}
          end)

        %{
          type: "pending",
          id: c.id,
          name: c.name,
          count: c.count,
          roll: c.roll,
          options: rendered_options,
          earned_at_level: Map.get(c, :earned_at_level)
        }

      %{type: :pending} = c ->
        %{type: "pending", id: c.id, name: c.name, count: c.count, roll: c.roll}

      %{type: :available} = c ->
        %{type: "available", id: c.id, name: c.name, roll: c.roll}
    end)
  end

  defp find_display_template(system, concept_type) do
    Enum.find_value(system.module.concept_types, fn ct ->
      if ct.id == concept_type, do: ct.display_template
    end)
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
