defmodule ExTTRPGDev.CLI.CharacterDisplay do
  @moduledoc """
  Formats and prints a character sheet to stdout.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystem.Evaluator
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Evaluates `character` against `system` and prints a formatted character sheet.

  Groups resolved values by entity type (in declaration order) and skips entity
  types that have no DAG nodes (e.g. pure-metadata types like languages).
  """
  def print(%LoadedSystem{} = system, %Character{} = character) do
    contributions = system.contributions ++ character.effects

    resolved =
      Evaluator.evaluate!(system, character.generated_values, contributions)

    resolved_by_entity = Enum.group_by(resolved, fn {{type, id, _field}, _} -> {type, id} end)

    IO.puts("-- #{character.name} --")

    Enum.each(system.package.entity_types, fn entity_type ->
      print_entity_type(entity_type, system.entity_metadata, resolved_by_entity)
    end)
  end

  defp print_entity_type(%{id: type_id, name: type_name}, entity_metadata, resolved_by_entity) do
    entities =
      entity_metadata
      |> Enum.filter(fn {{type, _id}, _} -> type == type_id end)
      |> Enum.sort_by(fn {{_type, id}, _} -> id end)
      |> Enum.filter(fn {{type, id}, _} -> Map.has_key?(resolved_by_entity, {type, id}) end)

    if entities != [] do
      IO.puts("\n#{type_name}s:")

      Enum.each(entities, fn {{type, id}, meta} ->
        print_entity(type, id, meta, resolved_by_entity)
      end)
    end
  end

  defp print_entity(type, id, meta, resolved_by_entity) do
    name = meta["name"] || id

    field_str =
      resolved_by_entity[{type, id}]
      |> Enum.sort_by(fn {{_t, _i, field}, _} -> field end)
      |> Enum.map_join("  ", fn {{_t, _i, field}, value} ->
        "#{field}: #{format_value(field, value)}"
      end)

    IO.puts("  #{name}: #{field_str}")
  end

  defp format_value("modifier", value) when is_integer(value) and value >= 0, do: "+#{value}"
  defp format_value(_field, value), do: "#{value}"
end
