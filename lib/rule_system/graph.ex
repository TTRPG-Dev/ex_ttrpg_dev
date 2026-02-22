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
    %{nodes: nodes, effects: effects} = loader_data

    graph =
      nodes
      |> Map.keys()
      |> Enum.reduce(Graph.new(type: :directed), &Graph.add_vertex(&2, &1))

    with {:ok, graph} <- add_formula_edges(graph, nodes),
         {:ok, graph} <- add_accumulator_edges(graph, nodes),
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

  defp add_formula_edges(graph, nodes) do
    Enum.reduce_while(nodes, {:ok, graph}, fn
      {node_key, %{type: :formula, formula: formula}}, {:ok, g} ->
        case validate_and_add_refs(g, nodes, formula, node_key) do
          {:ok, new_g} -> {:cont, {:ok, new_g}}
          error -> {:halt, error}
        end

      _, acc ->
        {:cont, acc}
    end)
  end

  defp add_accumulator_edges(graph, nodes) do
    Enum.reduce_while(nodes, {:ok, graph}, fn
      {node_key, %{type: :accumulator, base: base_formula}}, {:ok, g} ->
        case validate_and_add_refs(g, nodes, base_formula, node_key) do
          {:ok, new_g} -> {:cont, {:ok, new_g}}
          error -> {:halt, error}
        end

      _, acc ->
        {:cont, acc}
    end)
  end

  defp add_effect_edges(graph, nodes, effects) do
    Enum.reduce_while(effects, {:ok, graph}, fn
      %{target: target_key}, {:ok, g} when is_tuple(target_key) ->
        if Map.has_key?(nodes, target_key) do
          {:cont, {:ok, g}}
        else
          {:halt, {:error, {:undefined_effect_target, target_key}}}
        end

      _, acc ->
        {:cont, acc}
    end)
  end

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
