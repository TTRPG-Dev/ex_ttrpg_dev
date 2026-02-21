defmodule ExTTRPGDev.RuleSystem.Evaluator do
  @moduledoc """
  Evaluates a rule system DAG for a given character state.

  Takes the loaded system, a map of generated (base) values, and an optional
  list of active contributions (from equipped items, active feats, etc.),
  and produces a fully-resolved map of all node values.
  """

  alias ExTTRPGDev.RuleSystem.{Expression, Graph}

  @doc """
  Evaluates all nodes in the DAG in topological order.

  - `system` — output of `Graph.build/1`
  - `generated_values` — map of `{type_id, entity_id, field_name} => number` for generated nodes
  - `active_contributions` — list of `%{target: {type_id, entity_id, field_name}, value: number}`

  Returns `{:ok, resolved_map}` or `{:error, reason}`.
  """
  def evaluate(system, generated_values, active_contributions \\ []) do
    order = Graph.topological_order(system)

    Enum.reduce_while(order, {:ok, generated_values}, fn node_key, {:ok, resolved} ->
      case evaluate_node(node_key, system.nodes, resolved, active_contributions) do
        {:ok, value} -> {:cont, {:ok, Map.put(resolved, node_key, value)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @doc "Same as `evaluate/3` but raises on error."
  def evaluate!(system, generated_values, active_contributions \\ []) do
    case evaluate(system, generated_values, active_contributions) do
      {:ok, resolved} -> resolved
      {:error, reason} -> raise "Evaluation failed: #{inspect(reason)}"
    end
  end

  defp evaluate_node(node_key, nodes, resolved, active_contributions) do
    case Map.fetch(nodes, node_key) do
      {:ok, %{type: :generated}} ->
        fetch_generated(resolved, node_key)

      {:ok, %{type: :formula, formula: formula}} ->
        Expression.evaluate(formula, resolved)

      {:ok, %{type: :accumulator, base: base_formula}} ->
        evaluate_accumulator(base_formula, node_key, resolved, active_contributions)

      :error ->
        {:error, {:unknown_node, node_key}}
    end
  end

  defp evaluate_accumulator(base_formula, node_key, resolved, active_contributions) do
    with {:ok, base_value} <- Expression.evaluate(base_formula, resolved) do
      contrib_total =
        active_contributions
        |> Enum.filter(fn %{target: target} -> target == node_key end)
        |> Enum.map(fn %{value: v} -> v end)
        |> Enum.sum()

      {:ok, base_value + contrib_total}
    end
  end

  defp fetch_generated(resolved, node_key) do
    case Map.fetch(resolved, node_key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_generated_value, node_key}}
    end
  end
end
