defmodule ExTTRPGDev.CLI.CharacterDisplay do
  @moduledoc """
  Formats and prints a character sheet to stdout.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystem.Evaluator
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Evaluates `character` against `system` and prints a formatted character sheet.

  Groups resolved values by concept type (in declaration order) and skips concept
  types that have no DAG nodes (e.g. pure-metadata types like languages).
  """
  def print(%LoadedSystem{} = system, %Character{} = character) do
    contributions = system.contributions ++ character.effects

    resolved =
      Evaluator.evaluate!(system, character.generated_values, contributions)

    resolved_by_concept = Enum.group_by(resolved, fn {{type, id, _field}, _} -> {type, id} end)

    IO.puts("-- #{character.name} --")

    Enum.each(system.package.concept_types, fn concept_type ->
      print_concept_type(concept_type, system.concept_metadata, resolved_by_concept)
    end)
  end

  defp print_concept_type(%{id: type_id, name: type_name}, concept_metadata, resolved_by_concept) do
    concepts =
      concept_metadata
      |> Enum.filter(fn {{type, _id}, _} -> type == type_id end)
      |> Enum.sort_by(fn {{_type, id}, _} -> id end)
      |> Enum.filter(fn {{type, id}, _} -> Map.has_key?(resolved_by_concept, {type, id}) end)

    if concepts != [] do
      IO.puts("\n#{type_name}s:")

      Enum.each(concepts, fn {{type, id}, meta} ->
        print_concept(type, id, meta, resolved_by_concept)
      end)
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
