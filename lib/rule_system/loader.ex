defmodule ExTTRPGDev.RuleSystem.Loader do
  @moduledoc """
  Reads a rule system directory of TOML files and produces a unified data map
  ready for DAG construction.

  The output map has the shape:
  ```
  %{
    module: %RuleModule{},
    nodes: %{{type_id, concept_id, field_name} => node_map},
    rolling_methods: %{method_id => method_map},
    concept_metadata: %{{type_id, concept_id} => metadata_map},
    effects: [effect_map]
  }
  ```
  """

  alias ExTTRPGDev.RuleSystem.RuleModule

  @module_file "module.toml"

  @doc "Loads a rule system directory, returning `{:ok, data}` or `{:error, reason}`."
  def load(path) do
    with {:ok, rule_module} <- load_module(path),
         {:ok, data} <- load_concept_files(path, rule_module) do
      {:ok, Map.put(data, :module, rule_module)}
    end
  end

  @doc "Loads a rule system directory, raising on failure."
  def load!(path) do
    case load(path) do
      {:ok, data} -> data
      {:error, reason} -> raise "Failed to load rule system at #{path}: #{inspect(reason)}"
    end
  end

  defp load_module(path) do
    module_path = Path.join(path, @module_file)

    with {:ok, contents} <- File.read(module_path),
         {:ok, map} <- TomlElixir.decode(contents) do
      RuleModule.from_map(map)
    else
      {:error, reason} -> {:error, {:module_parse_error, reason}}
    end
  end

  defp load_concept_files(path, rule_module) do
    type_ids = RuleModule.concept_type_ids(rule_module)

    initial = %{nodes: %{}, rolling_methods: %{}, concept_metadata: %{}, effects: []}

    path
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".toml"))
    |> Enum.reject(&(&1 == @module_file))
    |> Enum.reduce_while({:ok, initial}, fn file, {:ok, acc} ->
      file_path = Path.join(path, file)

      with {:ok, contents} <- File.read(file_path),
           {:ok, toml_map} <- TomlElixir.decode(contents) do
        {:cont, {:ok, process_toml_map(toml_map, acc, type_ids)}}
      else
        {:error, reason} -> {:halt, {:error, {:file_parse_error, file, reason}}}
      end
    end)
  end

  defp process_toml_map(toml_map, acc, type_ids) do
    Enum.reduce(toml_map, acc, fn {type_id, concepts}, acc ->
      if MapSet.member?(type_ids, type_id) and is_map(concepts) do
        process_type(type_id, concepts, acc)
      else
        acc
      end
    end)
  end

  defp process_type("rolling_method", concepts, acc) do
    rolling_methods =
      Enum.reduce(concepts, acc.rolling_methods, fn {id, fields}, rm ->
        Map.put(rm, id, parse_rolling_method(fields))
      end)

    %{acc | rolling_methods: rolling_methods}
  end

  defp process_type(type_id, concepts, acc) do
    Enum.reduce(concepts, acc, fn {concept_id, fields}, acc ->
      process_concept(type_id, concept_id, fields, acc)
    end)
  end

  defp process_concept(type_id, concept_id, fields, acc) when is_map(fields) do
    {nodes, metadata, effects} = parse_concept_fields(type_id, concept_id, fields)

    %{
      acc
      | nodes: Map.merge(acc.nodes, nodes),
        concept_metadata: Map.put(acc.concept_metadata, {type_id, concept_id}, metadata),
        effects: acc.effects ++ effects
    }
  end

  defp parse_concept_fields(type_id, concept_id, fields) do
    Enum.reduce(fields, {%{}, %{}, []}, fn {field_name, value}, {nodes, meta, effects} ->
      cond do
        field_name == "contributes" and is_list(value) ->
          new_effects =
            Enum.map(value, &parse_effect({type_id, concept_id}, &1))

          {nodes, meta, effects ++ new_effects}

        is_map(value) and (Map.has_key?(value, "type") or Map.has_key?(value, "formula")) ->
          node_key = {type_id, concept_id, field_name}
          {Map.put(nodes, node_key, parse_node(value)), meta, effects}

        true ->
          {nodes, Map.put(meta, field_name, value), effects}
      end
    end)
  end

  defp parse_node(%{"type" => "generated"} = map) do
    %{type: :generated, method: Map.get(map, "method")}
  end

  defp parse_node(%{"type" => "accumulator"} = map) do
    %{type: :accumulator, base: Map.get(map, "base")}
  end

  defp parse_node(%{"formula" => formula}) do
    %{type: :formula, formula: formula}
  end

  defp parse_rolling_method(fields) do
    %{
      name: fields["name"],
      dice: fields["dice"],
      drop: fields["drop"],
      default: Map.get(fields, "default", false)
    }
  end

  defp parse_effect(source, %{"target" => target, "value" => value}) do
    parsed_target =
      case Regex.run(~r/(\w+)\('([^']+)'\)\.(\w+)/, target) do
        [_, type_id, concept_id, field_name] -> {type_id, concept_id, field_name}
        _ -> target
      end

    %{source: source, target: parsed_target, value: value}
  end
end
