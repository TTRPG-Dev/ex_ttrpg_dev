defmodule ExTTRPGDev.RuleSystem.Graph do
  @moduledoc """
  Builds and validates the dependency DAG for a rule system.

  Each node in the DAG is identified by a `{type_id, concept_id, field_name}` 3-tuple.
  Directed edges flow from dependency to dependent (e.g. `base_score` → `total_score`).
  """

  alias ExTTRPGDev.RuleSystem.Expression

  @doc """
  Builds a validated DAG from loader output.

  Returns `{:ok, system_map}` where `system_map` contains:
  - `:graph` — the libgraph `Graph.t()`
  - `:nodes` — node registry from the loader
  - `:rolling_methods`, `:concept_metadata`, `:effects` — passed through

  Returns `{:error, reason}` if any references are undefined.
  Raises if the graph contains cycles.
  """
  def build(loader_data) do
    %{nodes: nodes, effects: effects, concept_metadata: concept_metadata} = loader_data

    graph =
      nodes
      |> Map.keys()
      |> Enum.reduce(Graph.new(type: :directed), &Graph.add_vertex(&2, &1))

    with {:ok, _} <- validate_choice_options(concept_metadata),
         {:ok, graph} <- add_node_edges(graph, nodes),
         {:ok, graph} <- add_effect_edges(graph, nodes, effects) do
      if Graph.is_acyclic?(graph) do
        {:ok,
         %{
           graph: graph,
           nodes: nodes,
           rolling_methods: loader_data.rolling_methods,
           concept_metadata: loader_data.concept_metadata,
           effects: loader_data.effects
         }}
      else
        {:error, {:cycle_detected, "The rule system contains circular dependencies"}}
      end
    end
  end

  @doc "Returns nodes in topological evaluation order."
  def topological_order(%{graph: graph}) do
    Graph.topsort(graph)
  end

  defp validate_choice_options(concept_metadata) do
    valid_type_ids =
      concept_metadata
      |> Map.keys()
      |> MapSet.new(fn {type_id, _} -> type_id end)

    error =
      Enum.find_value(concept_metadata, fn {{type_id, concept_id}, meta} ->
        meta
        |> Map.get("choices", %{})
        |> Enum.find_value(fn {choice_id, choice_def} ->
          check_choice(
            {type_id, concept_id, choice_id},
            choice_def,
            valid_type_ids,
            concept_metadata
          )
        end)
      end)

    if error, do: error, else: {:ok, nil}
  end

  defp check_choice(
         {type_id, concept_id, choice_id},
         choice_def,
         valid_type_ids,
         concept_metadata
       ) do
    choice_type = choice_def["type"]
    options = Map.get(choice_def, "options", [])

    if MapSet.member?(valid_type_ids, choice_type) do
      missing = Enum.find(options, &(not Map.has_key?(concept_metadata, {choice_type, &1})))

      if missing do
        {:error,
         {:undefined_choice_option,
          "#{type_id}('#{concept_id}').choices.#{choice_id} option \"#{missing}\" not found in type \"#{choice_type}\""}}
      end
    else
      {:error,
       {:undefined_choice_type,
        "#{type_id}('#{concept_id}').choices.#{choice_id} references undefined type \"#{choice_type}\""}}
    end
  end

  defp add_node_edges(graph, nodes) do
    Enum.reduce_while(nodes, {:ok, graph}, fn {node_key, node}, {:ok, g} ->
      add_node_edge(g, nodes, node_key, node_formula(node))
    end)
  end

  defp add_node_edge(graph, _nodes, _node_key, nil), do: {:cont, {:ok, graph}}

  defp add_node_edge(graph, nodes, node_key, formula) do
    case validate_and_add_refs(graph, nodes, formula, node_key) do
      {:ok, new_g} -> {:cont, {:ok, new_g}}
      error -> {:halt, error}
    end
  end

  defp node_formula(%{type: :formula, formula: formula}), do: formula
  defp node_formula(%{type: :accumulator, base: base}), do: base
  defp node_formula(%{type: :mapping, input: input}), do: input
  defp node_formula(_), do: nil

  defp add_effect_edges(graph, nodes, effects) do
    Enum.reduce_while(effects, {:ok, graph}, fn effect, {:ok, g} ->
      case add_single_effect_edge(g, nodes, effect) do
        {:ok, new_g} -> {:cont, {:ok, new_g}}
        error -> {:halt, error}
      end
    end)
  end

  defp add_single_effect_edge(graph, nodes, %{target: target_key} = effect)
       when is_tuple(target_key) do
    if Map.has_key?(nodes, target_key) do
      add_formula_effect_edge(graph, nodes, target_key, effect.value)
    else
      {:error, {:undefined_effect_target, target_key}}
    end
  end

  defp add_single_effect_edge(graph, _nodes, _effect), do: {:ok, graph}

  defp add_formula_effect_edge(graph, nodes, target_key, value) when is_binary(value) do
    validate_and_add_refs(graph, nodes, value, target_key)
  end

  defp add_formula_effect_edge(graph, _nodes, _target_key, _value), do: {:ok, graph}

  defp validate_and_add_refs(graph, nodes, formula, dependent_key) do
    refs = Expression.extract_refs(formula)

    missing =
      Enum.find(refs, fn ref_key ->
        not Map.has_key?(nodes, ref_key)
      end)

    case missing do
      {type_id, concept_id, field_name} ->
        {:error,
         {:undefined_ref,
          "#{type_id}('#{concept_id}').#{field_name} referenced but not defined " <>
            "(depended on by #{inspect(dependent_key)})"}}

      nil ->
        new_graph =
          Enum.reduce(refs, graph, fn ref_key, g ->
            Graph.add_edge(g, ref_key, dependent_key)
          end)

        {:ok, new_graph}
    end
  end
end
