defmodule ExTTRPGDev.CLI.Serializer do
  @moduledoc """
  Converts domain objects (LoadedSystem, Character, etc.) into plain maps
  ready for JSON encoding. Extracted from Server to keep that module within
  code health thresholds.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, InventoryItem}
  alias ExTTRPGDev.CLI.ConceptDisplay
  alias ExTTRPGDev.RuleSystem.{Evaluator, InventoryRules}
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  def serialize_system(%LoadedSystem{module: mod}) do
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

  def serialize_concepts(%LoadedSystem{concept_metadata: meta}, concept_type) do
    concepts =
      meta
      |> Enum.filter(fn {{type, _id}, _} -> type == concept_type end)
      |> Enum.sort_by(fn {{_type, id}, _} -> id end)
      |> Enum.map(fn {{_type, id}, fields} ->
        %{id: id, name: Map.get(fields, "name", id)}
      end)

    %{concept_type: concept_type, concepts: concepts}
  end

  def serialize_character(
        %LoadedSystem{} = system,
        %Character{} = character,
        slug,
        display_mode
      ) do
    active = Characters.active_concepts(character.decisions, system.concept_metadata)
    effects = Characters.active_effects(system, character)
    resolved = Evaluator.evaluate!(system, character.generated_values, effects)
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

  def serialize_choices_list(choices, system, display_mode) do
    Enum.map(choices, fn
      %{type: :pending, options: options} = c ->
        concept_type = pending_choice_concept_type(c, system)
        template = find_display_template(system, concept_type)

        rendered_options =
          Enum.map(options, fn id ->
            fields = system.concept_metadata[{concept_type, id}] || %{"name" => id}
            %{id: id, label: ConceptDisplay.render(template, fields, display_mode)}
          end)

        base = %{
          type: "pending",
          id: c.id,
          name: c.name,
          count: c.count,
          roll: Map.get(c, :roll),
          options: rendered_options,
          earned_at_level: Map.get(c, :earned_at_level)
        }

        scope_extras = %{scope_type: Map.get(c, :scope_type), scope_id: Map.get(c, :scope_id)}
        Map.merge(base, Map.reject(scope_extras, fn {_, v} -> is_nil(v) end))

      %{type: :pending} = c ->
        %{type: "pending", id: c.id, name: c.name, count: c.count, roll: Map.get(c, :roll)}

      %{type: :available} = c ->
        %{type: "available", id: c.id, name: c.name, roll: Map.get(c, :roll)}
    end)
  end

  def serialize_resolutions(resolutions, system) do
    Enum.map(resolutions, fn r ->
      selection_name =
        r.concept_type &&
          r.selection_id &&
          get_in(system.concept_metadata, [{r.concept_type, r.selection_id}, "name"])

      %{
        name: r.name,
        selection_id: r.selection_id,
        selection_name: selection_name,
        rolled_value: r.rolled_value,
        method: r.method,
        earned_at_level: r.earned_at_level
      }
    end)
  end

  def serialize_building_choices(%LoadedSystem{} = system) do
    Enum.map(system.module.character_building_choices, fn cc ->
      concept_type = cc.concept_type
      template = find_display_template(system, concept_type)

      root_ids = MapSet.new(Characters.root_concept_ids(system.concept_metadata, concept_type))

      concepts =
        system.concept_metadata
        |> Enum.filter(fn {{type, id}, _} ->
          type == concept_type and MapSet.member?(root_ids, id)
        end)
        |> Enum.sort_by(fn {{_type, id}, _} -> id end)
        |> Enum.map(fn {{_type, id}, fields} ->
          %{id: id, label: ConceptDisplay.render(template, fields, :default)}
        end)

      types = system.module.concept_types
      ct_name = Enum.find_value(types, concept_type, &(&1.id == concept_type && &1.name))
      %{concept_type: concept_type, name: ct_name, concepts: concepts}
    end)
  end

  def serialize_inventory(inventory) do
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

  def serialize_concept_sub_choices(concept_type, concept_id, decisions, system) do
    scope_key = {concept_type, concept_id}
    choices = get_in(system.concept_metadata, [scope_key, "choices"]) || %{}

    already_chosen_by_type =
      decisions
      |> Enum.filter(&(&1.scope == scope_key))
      |> Enum.group_by(&(choices[&1.choice] || %{})["type"], & &1.selection)

    choices
    |> Enum.flat_map(fn {choice_id, choice_def} ->
      resolved = Enum.count(decisions, &(&1.scope == scope_key and &1.choice == choice_id))
      pending_count = if choice_def["required"] == true, do: max(0, 1 - resolved), else: 0

      render_pending_sub_choice_entry(
        choice_id,
        choice_def,
        concept_type,
        concept_id,
        pending_count,
        already_chosen_by_type,
        system
      )
    end)
    |> Enum.sort_by(& &1.id)
  end

  def fetch_choice_def!(system, {type, id}, choice_id) do
    get_in(system.concept_metadata, [{type, id}, "choices", choice_id]) ||
      raise("unknown choice #{inspect(choice_id)} on #{type}(#{id})")
  end

  def valid_sub_choices(system, {scope_type, scope_id} = scope, choice_def, decisions) do
    choice_type = choice_def["type"]
    raw_options = build_sub_choice_options(choice_def, choice_type, system)

    already_chosen =
      decisions
      |> Enum.filter(fn
        %{scope: ^scope, choice: choice} ->
          cd =
            get_in(system.concept_metadata, [{scope_type, scope_id}, "choices", choice]) || %{}

          cd["type"] == choice_type

        _ ->
          false
      end)
      |> MapSet.new(& &1.selection)

    Enum.reject(raw_options, &MapSet.member?(already_chosen, &1))
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

  defp pending_choice_concept_type(
         %{scope_type: scope_type, scope_id: scope_id, id: choice_id},
         system
       ) do
    get_in(system.concept_metadata, [{scope_type, scope_id}, "choices", choice_id, "type"])
  end

  defp pending_choice_concept_type(%{id: id}, system) do
    get_in(system.concept_metadata, [{"character_progression", id}, "type"])
  end

  defp find_display_template(system, concept_type) do
    Enum.find_value(system.module.concept_types, fn ct ->
      if ct.id == concept_type, do: ct.display_template
    end)
  end

  defp render_pending_sub_choice_entry(_, _, _, _, 0, _, _), do: []

  defp render_pending_sub_choice_entry(
         choice_id,
         choice_def,
         concept_type,
         concept_id,
         pending_count,
         already_chosen_by_type,
         system
       ) do
    choice_type = choice_def["type"]
    raw_options = build_sub_choice_options(choice_def, choice_type, system)
    excluded = MapSet.new(Map.get(already_chosen_by_type, choice_type, []))
    filtered = Enum.reject(raw_options, &MapSet.member?(excluded, &1))
    template = find_display_template(system, choice_type)

    rendered =
      Enum.map(filtered, fn id ->
        fields = system.concept_metadata[{choice_type, id}] || %{"name" => id}
        %{id: id, label: ConceptDisplay.render(template, fields, :default)}
      end)

    [
      %{
        type: "pending",
        id: choice_id,
        scope_type: concept_type,
        scope_id: concept_id,
        name: choice_def["name"] || choice_id,
        count: pending_count,
        options: rendered
      }
    ]
  end

  defp build_sub_choice_options(choice_def, choice_type, system) do
    case choice_def["options"] do
      options when is_list(options) ->
        options

      _ ->
        system.concept_metadata
        |> Enum.filter(fn {{t, _}, _} -> t == choice_type end)
        |> Enum.map(fn {{_, id}, _} -> id end)
        |> Enum.sort()
    end
  end
end
