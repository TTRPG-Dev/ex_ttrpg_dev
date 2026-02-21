defmodule ExTTRPGDev.RuleSystem.Loader do
  @moduledoc """
  Reads a rule system directory of TOML files and produces a unified data map
  ready for DAG construction.

  The output map has the shape:
  ```
  %{
    package: %Package{},
    nodes: %{{type_id, entity_id, field_name} => node_map},
    rolling_methods: %{method_id => method_map},
    entity_metadata: %{{type_id, entity_id} => metadata_map},
    contributions: [contribution_map]
  }
  ```
  """

  alias ExTTRPGDev.RuleSystem.Package

  @package_file "package.toml"

  @doc "Loads a rule system directory, returning `{:ok, data}` or `{:error, reason}`."
  def load(path) do
    with {:ok, package} <- load_package(path),
         {:ok, data} <- load_entity_files(path, package) do
      {:ok, Map.put(data, :package, package)}
    end
  end

  @doc "Loads a rule system directory, raising on failure."
  def load!(path) do
    case load(path) do
      {:ok, data} -> data
      {:error, reason} -> raise "Failed to load rule system at #{path}: #{inspect(reason)}"
    end
  end

  defp load_package(path) do
    package_path = Path.join(path, @package_file)

    with {:ok, contents} <- File.read(package_path),
         {:ok, map} <- TomlElixir.decode(contents) do
      Package.from_map(map)
    else
      {:error, reason} -> {:error, {:package_parse_error, reason}}
    end
  end

  defp load_entity_files(path, package) do
    entity_type_ids = Package.entity_type_ids(package)

    initial = %{nodes: %{}, rolling_methods: %{}, entity_metadata: %{}, contributions: []}

    path
    |> File.ls!()
    |> Enum.filter(&String.ends_with?(&1, ".toml"))
    |> Enum.reject(&(&1 == @package_file))
    |> Enum.reduce_while({:ok, initial}, fn file, {:ok, acc} ->
      file_path = Path.join(path, file)

      with {:ok, contents} <- File.read(file_path),
           {:ok, toml_map} <- TomlElixir.decode(contents) do
        {:cont, {:ok, process_toml_map(toml_map, acc, entity_type_ids)}}
      else
        {:error, reason} -> {:halt, {:error, {:file_parse_error, file, reason}}}
      end
    end)
  end

  defp process_toml_map(toml_map, acc, entity_type_ids) do
    Enum.reduce(toml_map, acc, fn {type_id, entities}, acc ->
      if MapSet.member?(entity_type_ids, type_id) and is_map(entities) do
        process_entity_type(type_id, entities, acc)
      else
        acc
      end
    end)
  end

  defp process_entity_type("rolling_method", entities, acc) do
    rolling_methods =
      Enum.reduce(entities, acc.rolling_methods, fn {id, fields}, rm ->
        Map.put(rm, id, parse_rolling_method(fields))
      end)

    %{acc | rolling_methods: rolling_methods}
  end

  defp process_entity_type(type_id, entities, acc) do
    Enum.reduce(entities, acc, fn {entity_id, fields}, acc ->
      process_entity(type_id, entity_id, fields, acc)
    end)
  end

  defp process_entity(type_id, entity_id, fields, acc) when is_map(fields) do
    {nodes, metadata, contributions} = parse_entity_fields(type_id, entity_id, fields)

    %{
      acc
      | nodes: Map.merge(acc.nodes, nodes),
        entity_metadata: Map.put(acc.entity_metadata, {type_id, entity_id}, metadata),
        contributions: acc.contributions ++ contributions
    }
  end

  defp parse_entity_fields(type_id, entity_id, fields) do
    Enum.reduce(fields, {%{}, %{}, []}, fn {field_name, value}, {nodes, meta, contribs} ->
      cond do
        field_name == "contributes" and is_list(value) ->
          new_contribs =
            Enum.map(value, &parse_contribution({type_id, entity_id}, &1))

          {nodes, meta, contribs ++ new_contribs}

        is_map(value) and (Map.has_key?(value, "type") or Map.has_key?(value, "formula")) ->
          node_key = {type_id, entity_id, field_name}
          {Map.put(nodes, node_key, parse_node(value)), meta, contribs}

        true ->
          {nodes, Map.put(meta, field_name, value), contribs}
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

  defp parse_contribution(source, %{"target" => target, "value" => value}) do
    parsed_target =
      case Regex.run(~r/(\w+)\('([^']+)'\)\.(\w+)/, target) do
        [_, type_id, entity_id, field_name] -> {type_id, entity_id, field_name}
        _ -> target
      end

    %{source: source, target: parsed_target, value: value}
  end
end
