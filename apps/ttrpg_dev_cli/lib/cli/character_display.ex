defmodule ExTTRPGDev.CLI.CharacterDisplay do
  @moduledoc """
  Formats and prints a character sheet to stdout.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystem.Evaluator
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Evaluates `character` against `system` and prints a formatted character sheet.

  Groups resolved values by concept type (in declaration order) and skips concept
  types that have no DAG nodes (e.g. pure-metadata types like languages).
  """
  def print(%LoadedSystem{} = system, %Character{} = character) do
    resolved =
      system
      |> Characters.active_effects(character)
      |> then(&Evaluator.evaluate!(system, character.generated_values, &1))

    resolved_by_concept = Enum.group_by(resolved, fn {{type, id, _field}, _} -> {type, id} end)

    IO.puts("-- #{character.name} --")
    print_character_choices(system, character)
    print_known_languages(system, character)
    print_weapon_proficiencies(system, character)
    print_armor_proficiencies(system, character)
    print_tool_proficiencies(system, character)

    Enum.each(system.module.concept_types, fn concept_type ->
      print_concept_type(concept_type, system.concept_metadata, resolved_by_concept)
    end)
  end

  defp print_character_choices(system, character) do
    Enum.each(system.module.character_choices, fn %{concept_type: type_id} ->
      type_name = Enum.find_value(system.module.concept_types, &if(&1.id == type_id, do: &1.name))
      root = Enum.find(character.decisions, &(&1.scope == nil and &1.choice == type_id))

      if root do
        chain =
          concept_name_chain(
            character.decisions,
            system.concept_metadata,
            type_id,
            root.selection
          )

        IO.puts("#{type_name}: #{Enum.join(chain, " / ")}")
      end
    end)
  end

  # Builds the display name chain for a concept, following only sub-choices of the
  # same type (e.g. race → subrace, but not race → equipment or race → language).
  defp concept_name_chain(decisions, concept_metadata, type_id, concept_id) do
    name = get_in(concept_metadata, [{type_id, concept_id}, "name"]) || concept_id

    sub_names =
      concept_metadata
      |> Map.get({type_id, concept_id}, %{})
      |> Map.get("choices", %{})
      |> Enum.flat_map(fn {choice_id, choice_def} ->
        same_type_sub_chain(
          decisions,
          concept_metadata,
          type_id,
          concept_id,
          choice_id,
          choice_def
        )
      end)

    [name | sub_names]
  end

  defp same_type_sub_chain(
         decisions,
         concept_metadata,
         type_id,
         concept_id,
         choice_id,
         choice_def
       ) do
    if choice_def["type"] == type_id do
      decision =
        Enum.find(decisions, &(&1.scope == {type_id, concept_id} and &1.choice == choice_id))

      if decision do
        concept_name_chain(decisions, concept_metadata, type_id, decision.selection)
      else
        []
      end
    else
      []
    end
  end

  defp print_known_languages(system, character) do
    active = Characters.active_concepts(character.decisions, system.concept_metadata)

    fixed =
      active
      |> Enum.flat_map(fn {type, id} ->
        Map.get(system.concept_metadata[{type, id}] || %{}, "languages", [])
      end)

    chosen =
      character.decisions
      |> Enum.filter(fn
        %{scope: {scope_type, scope_id}, choice: choice_id} ->
          get_in(system.concept_metadata, [
            {scope_type, scope_id},
            "choices",
            choice_id,
            "type"
          ]) == "language"

        _ ->
          false
      end)
      |> Enum.map(& &1.selection)

    all_langs = (fixed ++ chosen) |> Enum.uniq() |> Enum.sort()

    if all_langs != [] do
      names =
        Enum.map(all_langs, fn id ->
          get_in(system.concept_metadata, [{"language", id}, "name"]) || id
        end)

      IO.puts("Languages: #{Enum.join(names, ", ")}")
    end
  end

  defp print_weapon_proficiencies(system, character) do
    active = Characters.active_concepts(character.decisions, system.concept_metadata)

    all_weapons =
      active
      |> Enum.flat_map(fn {type, id} ->
        Map.get(system.concept_metadata[{type, id}] || %{}, "weapon_proficiencies", [])
      end)
      |> Enum.uniq()
      |> Enum.sort()

    if all_weapons != [] do
      names =
        Enum.map(all_weapons, fn id ->
          get_in(system.concept_metadata, [{"equipment", id}, "name"]) || id
        end)

      IO.puts("Weapon Proficiencies: #{Enum.join(names, ", ")}")
    end
  end

  defp print_armor_proficiencies(system, character) do
    active = Characters.active_concepts(character.decisions, system.concept_metadata)

    all_armor =
      active
      |> Enum.flat_map(fn {type, id} ->
        Map.get(system.concept_metadata[{type, id}] || %{}, "armor_proficiencies", [])
      end)
      |> Enum.uniq()
      |> Enum.sort()

    if all_armor != [] do
      names = Enum.map(all_armor, &format_armor_category/1)
      IO.puts("Armor Proficiencies: #{Enum.join(names, ", ")}")
    end
  end

  defp format_armor_category("shield"), do: "Shield"
  defp format_armor_category(category), do: "#{String.capitalize(category)} Armor"

  defp print_tool_proficiencies(system, character) do
    active = Characters.active_concepts(character.decisions, system.concept_metadata)

    fixed =
      active
      |> Enum.flat_map(fn {type, id} ->
        Map.get(system.concept_metadata[{type, id}] || %{}, "tool_proficiencies", [])
      end)

    chosen =
      character.decisions
      |> Enum.filter(fn
        %{scope: {scope_type, scope_id}, choice: choice_id} ->
          get_in(system.concept_metadata, [
            {scope_type, scope_id},
            "choices",
            choice_id,
            "type"
          ]) == "equipment"

        _ ->
          false
      end)
      |> Enum.map(& &1.selection)

    all_tools = (fixed ++ chosen) |> Enum.uniq() |> Enum.sort()

    if all_tools != [] do
      names =
        Enum.map(all_tools, fn id ->
          get_in(system.concept_metadata, [{"equipment", id}, "name"]) || id
        end)

      IO.puts("Tool Proficiencies: #{Enum.join(names, ", ")}")
    end
  end

  defp print_concept_type(%{id: type_id, name: type_name}, concept_metadata, resolved_by_concept) do
    concepts =
      concept_metadata
      |> Enum.filter(fn {{type, _id}, _} -> type == type_id end)
      |> Enum.sort_by(fn {{_type, id}, _} -> id end)
      |> Enum.filter(fn {{type, id}, _} -> Map.has_key?(resolved_by_concept, {type, id}) end)

    if concepts != [] do
      IO.puts("\n#{pluralize(type_name)}:")

      Enum.each(concepts, fn {{type, id}, meta} ->
        print_concept(type, id, meta, resolved_by_concept)
      end)
    end
  end

  defp pluralize(word) do
    if String.ends_with?(word, "y") do
      String.slice(word, 0..-2//1) <> "ies"
    else
      word <> "s"
    end
  end

  defp print_concept(type, id, meta, resolved_by_concept) do
    name = meta["name"] || id

    field_str =
      resolved_by_concept[{type, id}]
      |> Enum.sort_by(fn {{_t, _i, field}, _} -> field end)
      |> Enum.map_join("  ", fn {{_t, _i, field}, value} ->
        "#{field}: #{format_value(field, value)}"
      end)

    IO.puts("  #{name}: #{field_str}")
  end

  defp format_value("modifier", value) when is_integer(value) and value >= 0, do: "+#{value}"
  defp format_value(_field, value), do: "#{value}"
end
