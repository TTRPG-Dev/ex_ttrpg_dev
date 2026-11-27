defmodule ExTTRPGDev.RuleSystem.Evaluator do
  @moduledoc """
  Evaluates a rule system DAG for a given character state.

  Takes the loaded system, a map of generated (base) values, and an optional
  list of active effects (from equipped items, active feats, etc.),
  and produces a fully-resolved map of all node values.
  """

  alias ExTTRPGDev.RuleSystem.{Dice, Effect, Expression, Graph, Node}

  @doc """
  Evaluates all nodes in the DAG in topological order.

  - `system` — output of `Graph.build/1`
  - `generated_values` — map of `{type_id, concept_id, field_name} => number` for generated nodes
  - `effects` — list of `%Effect{target: {type_id, concept_id, field_name}, value: number}`

  Returns `{:ok, resolved_map}` or `{:error, reason}`.

  ## Example

  Given a system with an `"ability"` type whose `base_score` is a generated
  node and whose `modifier` is a formula node derived from it, resolving a
  base score of 10 yields a modifier of 0:

      system = load_system!(...)
      generated = %{{"ability", "strength", "base_score"} => 10}
      {:ok, resolved} = Evaluator.evaluate(system, generated)
      resolved[{"ability", "strength", "modifier"}]
      #=> 0

  See `ExTTRPGDev.RuleSystem.EvaluatorTest` for a runnable version of this
  example built from a minimal fixture system.
  """
  def evaluate(system, generated_values, effects \\ []) do
    order = Graph.topological_order(system)

    Enum.reduce_while(order, {:ok, generated_values}, fn node_key, {:ok, resolved} ->
      case evaluate_node(node_key, system.nodes, resolved, effects) do
        {:ok, value} -> {:cont, {:ok, Map.put(resolved, node_key, value)}}
        {:error, _} = err -> {:halt, err}
      end
    end)
  end

  @doc "Same as `evaluate/3` but raises on error."
  def evaluate!(system, generated_values, effects \\ []) do
    case evaluate(system, generated_values, effects) do
      {:ok, resolved} -> resolved
      {:error, reason} -> raise "Evaluation failed: #{inspect(reason)}"
    end
  end

  defp evaluate_node(node_key, nodes, resolved, effects) do
    case Map.fetch(nodes, node_key) do
      {:ok, %Node{type: :generated}} ->
        fetch_generated(resolved, node_key)

      {:ok, %Node{type: :formula, formula: formula}} ->
        Expression.evaluate(formula, resolved)

      {:ok, %Node{type: :accumulator, base: base_formula}} ->
        evaluate_accumulator(base_formula, node_key, resolved, effects)

      {:ok, %Node{type: :mapping, input: input_formula, steps: steps}} ->
        evaluate_mapping(input_formula, steps, resolved)

      :error ->
        {:error, {:unknown_node, node_key}}
    end
  end

  defp evaluate_accumulator(base_formula, node_key, resolved, effects) do
    with {:ok, base_value} <- Expression.evaluate(base_formula, resolved) do
      effects
      |> Enum.filter(fn %Effect{target: target} -> target == node_key end)
      |> Enum.reduce_while({:ok, base_value}, &apply_effect(&1, &2, resolved))
    end
  end

  # An accumulator's base may be dice (e.g. `base = "dice(1, 6)"`), in
  # which case contributions follow the same rules as `+` in a formula.
  defp accumulate(acc, n, _target) when is_number(acc) and is_number(n), do: {:ok, acc + n}

  defp accumulate(acc, n, target) do
    case Dice.add(acc, n) do
      {:ok, _} = ok -> ok
      {:error, message} -> {:error, {:invalid_contribution, message, target}}
    end
  end

  defp apply_effect(
         %Effect{when: condition, item_fields: item_fields} = effect,
         {:ok, acc},
         resolved
       ) do
    with {:ok, true} <- evaluate_condition(condition, resolved, item_fields),
         {:ok, n} <- resolve_effect_value(effect.value, resolved, item_fields),
         {:ok, acc} <- accumulate(acc, n, effect.target) do
      {:cont, {:ok, acc}}
    else
      {:ok, false} -> {:cont, {:ok, acc}}
      error -> {:halt, error}
    end
  end

  defp evaluate_condition(nil, _resolved, _item_fields), do: {:ok, true}

  defp evaluate_condition(formula, resolved, item_fields) when is_binary(formula) do
    case formula |> substitute_item_fields(item_fields) |> Expression.evaluate(resolved) do
      {:ok, result} -> truthy(result, formula)
      error -> error
    end
  end

  defp truthy(b, _formula) when is_boolean(b), do: {:ok, b}
  defp truthy(n, _formula) when is_number(n), do: {:ok, n != 0}

  # Dice (or any future non-scalar value) have no truth value; treating them
  # as false would silently drop the effect.
  defp truthy(value, formula) do
    {:error,
     {:eval_error, "condition must be a boolean or number, got: #{inspect(value)}", formula}}
  end

  defp resolve_effect_value(value, _resolved, _item_fields) when is_number(value),
    do: {:ok, value}

  defp resolve_effect_value(formula, resolved, item_fields) when is_binary(formula) do
    formula |> substitute_item_fields(item_fields) |> Expression.evaluate(resolved)
  end

  # A single greedy-regex pass: `item.bonus_max` always matches its full
  # field name, so fields sharing a prefix (item.bonus / item.bonus_max)
  # cannot corrupt each other the way per-field String.replace passes did.
  # Unknown fields are left untouched and surface as a parse error.
  defp substitute_item_fields(formula, item_fields) do
    Regex.replace(~r/item\.(\w+)/, formula, fn full, name ->
      case Map.fetch(item_fields, name) do
        {:ok, value} -> to_string(value)
        :error -> full
      end
    end)
  end

  defp evaluate_mapping(input_formula, steps, resolved) do
    with {:ok, input_value} <- Expression.evaluate(input_formula, resolved) do
      resolve_mapping_step(steps, input_value)
    end
  end

  @doc """
  Resolves a mapping node's `steps` for a given already-evaluated `input_value`:
  the value of the last step whose threshold is `<= input_value`.

  Exposed so callers that already know a mapping node's input value (e.g.
  computing a character's current level from accumulated XP) can reuse this
  instead of re-implementing the same threshold-matching rule.

  Returns `{:ok, value}`, `{:error, {:mapping_no_match, input_value}}`, or
  `{:error, {:mapping_non_numeric_input, input_value}}` when the input isn't a
  number (e.g. dice) — Erlang orders every struct above every number, so
  comparing one against thresholds would silently pick the last step.
  """
  def resolve_mapping_step(_steps, input_value) when not is_number(input_value),
    do: {:error, {:mapping_non_numeric_input, input_value}}

  def resolve_mapping_step(steps, input_value) do
    steps
    |> Enum.filter(fn [threshold, _] -> input_value >= threshold end)
    |> List.last()
    |> case do
      [_, output] -> {:ok, output}
      nil -> {:error, {:mapping_no_match, input_value}}
    end
  end

  defp fetch_generated(resolved, node_key) do
    case Map.fetch(resolved, node_key) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, {:missing_generated_value, node_key}}
    end
  end
end
