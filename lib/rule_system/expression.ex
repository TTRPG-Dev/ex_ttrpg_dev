defmodule ExTTRPGDev.RuleSystem.Expression do
  @moduledoc """
  Handles the expression sub-language used in rule system formula nodes.

  Formulas use the syntax `entity_type('entity_id').field` to reference other nodes.
  For example: `floor((attr('dexterity').total_score - 10) / 2)`

  These references create edges in the DAG. When evaluating, all references are
  substituted with their resolved numeric values before expression evaluation.
  """

  @ref_pattern ~r/(\w+)\('([^']+)'\)\.(\w+)/

  @doc """
  Extracts all entity references from a formula string.

  Returns a list of `{type_id, entity_id, field_name}` tuples representing
  DAG dependencies declared by the formula.

  ## Examples

      iex> ExTTRPGDev.RuleSystem.Expression.extract_refs("floor((attr('dexterity').total_score - 10) / 2)")
      [{"attr", "dexterity", "total_score"}]

      iex> ExTTRPGDev.RuleSystem.Expression.extract_refs("attr('strength').modifier")
      [{"attr", "strength", "modifier"}]

      iex> ExTTRPGDev.RuleSystem.Expression.extract_refs("42")
      []

  """
  def extract_refs(formula) do
    @ref_pattern
    |> Regex.scan(formula)
    |> Enum.map(fn [_full, type_id, entity_id, field_name] ->
      {type_id, entity_id, field_name}
    end)
    |> Enum.uniq()
  end

  @doc """
  Evaluates a formula string given a map of resolved node values.

  Substitutes all `type('id').field` references in the formula with their
  resolved numeric values from `bindings`, then evaluates the resulting
  expression.

  Returns `{:ok, number}` or `{:error, reason}`.

  ## Examples

      iex> bindings = %{{"attr", "dexterity", "total_score"} => 18}
      iex> ExTTRPGDev.RuleSystem.Expression.evaluate("floor((attr('dexterity').total_score - 10) / 2)", bindings)
      {:ok, 4}

      iex> bindings = %{{"attr", "strength", "base_score"} => 14}
      iex> ExTTRPGDev.RuleSystem.Expression.evaluate("attr('strength').base_score", bindings)
      {:ok, 14}

  """
  def evaluate(formula, bindings) do
    refs = extract_refs(formula)

    missing = Enum.find(refs, fn ref -> not Map.has_key?(bindings, ref) end)

    if missing do
      {type_id, entity_id, field_name} = missing
      {:error, {:missing_binding, "#{type_id}('#{entity_id}').#{field_name}"}}
    else
      processed =
        Enum.reduce(bindings, formula, fn {{type_id, entity_id, field_name}, value}, acc ->
          ref_str = "#{type_id}('#{entity_id}').#{field_name}"
          String.replace(acc, ref_str, to_string(value))
        end)

      try do
        {result, _bindings} = Code.eval_string(processed)
        {:ok, result}
      rescue
        e -> {:error, {:eval_error, Exception.message(e), processed}}
      end
    end
  end
end
