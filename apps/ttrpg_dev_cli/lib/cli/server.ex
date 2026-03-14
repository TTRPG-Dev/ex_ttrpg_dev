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
      {"command": "characters.add_effect", "character": "thorin-stoneback", "target": "character_trait('experience_points').total", "value": 300}
      {"command": "characters.choices", "character": "thorin-stoneback"}
      {"command": "characters.resolve_choice", "character": "thorin-stoneback", "progression": "hp_per_level", "value": 7, "selection": "rolled"}

  Each response is a single line of JSON:

      {"status": "ok", "data": {...}}
      {"status": "error", "message": "..."}

  Generated-but-unsaved characters are held in memory under a `temp_id` until
  `characters.save` is called or the server exits.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Dice
  alias ExTTRPGDev.RuleSystem.Evaluator
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

      data = Map.put(serialize_character(system, character, nil), :temp_id, temp_id)
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
           "command" => "characters.add_effect",
           "character" => slug,
           "target" => target,
           "value" => value
         },
         state
       ) do
    try do
      unless is_integer(value), do: raise("value must be an integer")

      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      parsed_target = parse_effect_target!(target)

      updated = %{
        character
        | effects: character.effects ++ [%{target: parsed_target, value: value}]
      }

      Characters.save_character!(updated, true)

      resolved = resolve_character(system, updated)
      choices = Characters.pending_choices(system, updated, resolved)

      data =
        serialize_character(system, updated, slug)
        |> Map.put(:pending_choices, serialize_choices_list(choices))

      {ok(data), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(%{"command" => "characters.choices", "character" => slug}, state) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      resolved = resolve_character(system, character)
      choices = Characters.pending_choices(system, character, resolved)

      {ok(%{pending_choices: serialize_choices_list(choices)}), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(
         %{
           "command" => "characters.resolve_choice",
           "character" => slug,
           "progression" => progression_id,
           "value" => value,
           "selection" => selection
         },
         state
       ) do
    try do
      unless is_integer(value), do: raise("value must be an integer")

      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)

      parsed_target = load_progression_target!(system, progression_id)

      choice_number =
        Enum.count(character.decisions, fn
          %{scope: {"character_progression", ^progression_id}} -> true
          _ -> false
        end) + 1

      updated = %{
        character
        | effects: character.effects ++ [%{target: parsed_target, value: value}],
          decisions:
            character.decisions ++
              [
                %{
                  scope: {"character_progression", progression_id},
                  choice: "choice_#{choice_number}",
                  selection: selection
                }
              ]
      }

      Characters.save_character!(updated, true)

      resolved = resolve_character(system, updated)
      choices = Characters.pending_choices(system, updated, resolved)

      data =
        serialize_character(system, updated, slug)
        |> Map.put(:pending_choices, serialize_choices_list(choices))

      {ok(data), state}
    rescue
      e -> {error(Exception.message(e)), state}
    end
  end

  defp handle(%{"command" => "characters.show", "character" => slug}, state) do
    try do
      character = Characters.load_character!(slug)
      system = RuleSystems.load_system!(character.metadata.rule_system)
      data = serialize_character(system, character, slug)
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

  defp serialize_character(%LoadedSystem{} = system, %Character{} = character, slug) do
    active = Characters.active_concepts(character.decisions, system.concept_metadata)
    resolved = resolve_character(system, character)
    resolved_by_concept = Enum.group_by(resolved, fn {{type, id, _field}, _} -> {type, id} end)

    %{
      name: character.name,
      rule_system: character.metadata.rule_system,
      slug: slug,
      hit_die: get_hit_die(character, system.concept_metadata),
      choices: serialize_choices(system, character),
      proficiencies: serialize_proficiencies(system, character, active),
      concept_types: serialize_concept_type_values(system, resolved_by_concept)
    }
  end

  defp get_hit_die(character, concept_metadata) do
    case Enum.find(character.decisions, &(&1.scope == nil and &1.choice == "class")) do
      nil -> nil
      %{selection: class_id} -> get_in(concept_metadata, [{"class", class_id}, "hit_die"])
    end
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

  defp serialize_proficiencies(%LoadedSystem{} = system, %Character{} = character, active) do
    skill_ids = collect_from_active(active, system.concept_metadata, "skill_proficiencies")
    weapon_ids = collect_from_active(active, system.concept_metadata, "weapon_proficiencies")
    armor_ids = collect_from_active(active, system.concept_metadata, "armor_proficiencies")

    fixed_langs = collect_from_active(active, system.concept_metadata, "languages")
    chosen_langs = chosen_by_type(character.decisions, system.concept_metadata, "language")
    all_langs = (fixed_langs ++ chosen_langs) |> Enum.uniq() |> Enum.sort()

    fixed_tools = collect_from_active(active, system.concept_metadata, "tool_proficiencies")
    chosen_tools = chosen_by_type(character.decisions, system.concept_metadata, "equipment")
    all_tools = (fixed_tools ++ chosen_tools) |> Enum.uniq() |> Enum.sort()

    %{
      skills:
        Enum.map(skill_ids, fn id ->
          get_in(system.concept_metadata, [{"skill", id}, "name"]) || id
        end),
      languages:
        Enum.map(all_langs, fn id ->
          get_in(system.concept_metadata, [{"language", id}, "name"]) || id
        end),
      weapons:
        Enum.map(weapon_ids, fn id ->
          get_in(system.concept_metadata, [{"equipment", id}, "name"]) || id
        end),
      armor: Enum.map(armor_ids, &format_armor_category/1),
      tools:
        Enum.map(all_tools, fn id ->
          get_in(system.concept_metadata, [{"equipment", id}, "name"]) || id
        end)
    }
  end

  defp format_armor_category("shield"), do: "Shield"
  defp format_armor_category(category), do: "#{String.capitalize(category)} Armor"

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
        get_in(concept_metadata, [{scope_type, scope_id}, "choices", choice_id, "type"]) == type

      _ ->
        false
    end)
    |> Enum.map(& &1.selection)
  end

  defp serialize_concept_type_values(%LoadedSystem{} = system, resolved_by_concept) do
    system.module.concept_types
    |> Enum.flat_map(&serialize_concept_type(&1, system.concept_metadata, resolved_by_concept))
  end

  defp serialize_concept_type(concept_type, concept_metadata, resolved_by_concept) do
    concepts =
      concept_metadata
      |> Enum.filter(fn {{type, _id}, _} -> type == concept_type.id end)
      |> Enum.sort_by(fn {{_type, id}, _} -> id end)
      |> Enum.filter(fn {{type, id}, _} -> Map.has_key?(resolved_by_concept, {type, id}) end)

    if concepts == [] do
      []
    else
      entries = Enum.map(concepts, &serialize_concept_entry(&1, resolved_by_concept))
      [%{id: concept_type.id, name: concept_type.name, concepts: entries}]
    end
  end

  defp serialize_concept_entry({{type, id}, meta}, resolved_by_concept) do
    name = meta["name"] || id

    fields =
      resolved_by_concept[{type, id}]
      |> Enum.sort_by(fn {{_t, _i, field}, _} -> field end)
      |> Enum.map(fn {{_t, _i, field}, value} ->
        %{name: field, value: format_field_value(field, value)}
      end)

    %{id: id, name: name, fields: fields}
  end

  defp format_field_value("modifier", value) when is_integer(value) and value >= 0,
    do: "+#{value}"

  defp format_field_value(_field, value), do: "#{value}"

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

  @effect_target_regex ~r/^(\w+)\('([^']+)'\)\.(\w+)$/

  defp parse_effect_target!(target) do
    case Regex.run(@effect_target_regex, target, capture: :all_but_first) do
      [type_id, concept_id, field] -> {type_id, concept_id, field}
      _ -> raise("invalid effect target: #{inspect(target)}")
    end
  end

  defp serialize_choices_list(choices) do
    Enum.map(choices, fn
      %{type: :pending} = c ->
        %{type: "pending", id: c.id, name: c.name, count: c.count, roll: c.roll}

      %{type: :available} = c ->
        %{type: "available", id: c.id, name: c.name, roll: c.roll}
    end)
  end

  # --- Response helpers ---

  defp ok(data), do: %{status: "ok", data: data}
  defp error(message), do: %{status: "error", message: message}
end
