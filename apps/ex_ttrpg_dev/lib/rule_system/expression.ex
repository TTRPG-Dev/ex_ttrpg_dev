defmodule ExTTRPGDev.RuleSystem.Expression do
  @moduledoc """
  Handles the expression sub-language used in rule system formula nodes.

  Formulas use the syntax `type('concept_id').field` to reference other nodes.
  For example: `floor((attr('dexterity').total_score - 10) / 2)`

  These references create edges in the DAG. When evaluating, references are
  resolved against the bindings map as part of expression evaluation.

  ## Grammar

  Formulas are parsed and evaluated against a closed grammar; they cannot
  execute arbitrary code. Supported constructs:

    * number literals — integers (`42`) and floats (`2.5`)
    * boolean literals — `true`, `false`
    * node references — `type('concept_id').field`
    * arithmetic — `+`, `-`, `*`, `/` (`/` is float division; wrap in
      `floor(...)` for integer results) and unary minus
    * comparison — `>`, `<`, `>=`, `<=`, `==`, `!=` (numbers only)
    * boolean logic — `and`, `or`, `not` (booleans only)
    * grouping — `( ... )`
    * functions — `floor/1`, `ceil/1`, `trunc/1`, `abs/1`, `min/2`, `max/2`

  Anything outside this grammar returns `{:error, {:parse_error, message,
  formula}}`; calling an unknown function returns `{:error, {:eval_error,
  message, formula}}`.
  """

  @ref_pattern ~r/(\w+)\('([^']+)'\)\.(\w+)/
  @single_ref_pattern Regex.compile!("^" <> Regex.source(@ref_pattern) <> "$")
  @leading_ref_pattern Regex.compile!("^" <> Regex.source(@ref_pattern))

  @doc """
  Extracts all concept references from a formula string.

  Returns a list of `{type_id, concept_id, field_name}` tuples representing
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
    |> Enum.map(fn [_full, type_id, concept_id, field_name] ->
      {type_id, concept_id, field_name}
    end)
    |> Enum.uniq()
  end

  @doc """
  Parses a string consisting of exactly one node reference.

  Unlike `extract_refs/1`, the whole string must be a single reference —
  use this for values that are node keys (e.g. effect targets), not
  formulas.

  Returns `{:ok, {type_id, concept_id, field_name}}` or `:error`.

  ## Examples

      iex> ExTTRPGDev.RuleSystem.Expression.parse_ref("ability('strength').modifier")
      {:ok, {"ability", "strength", "modifier"}}

      iex> ExTTRPGDev.RuleSystem.Expression.parse_ref("ability(strength).modifier")
      :error

      iex> ExTTRPGDev.RuleSystem.Expression.parse_ref("ability('strength').modifier + 1")
      :error

  """
  def parse_ref(string) when is_binary(string) do
    case Regex.run(@single_ref_pattern, string, capture: :all_but_first) do
      [type_id, concept_id, field_name] -> {:ok, {type_id, concept_id, field_name}}
      nil -> :error
    end
  end

  @doc """
  Evaluates a formula string given a map of resolved node values.

  Node references in the formula are looked up in `bindings` (keyed by
  `{type_id, concept_id, field_name}`), and the expression is evaluated
  against the whitelisted grammar documented in the moduledoc.

  Returns `{:ok, number | boolean}` or `{:error, reason}`.

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
      {type_id, concept_id, field_name} = missing
      {:error, {:missing_binding, "#{type_id}('#{concept_id}').#{field_name}"}}
    else
      with {:ok, ast} <- parse(formula),
           {:ok, value} <- eval_ast(ast, bindings) do
        {:ok, value}
      else
        {:error, {:parse_error, message}} -> {:error, {:parse_error, message, formula}}
        {:error, {:eval_error, message}} -> {:error, {:eval_error, message, formula}}
      end
    end
  end

  @doc """
  Parses a formula string into an AST, without evaluating it.

  Useful for validating formulas at load time. Returns `{:ok, ast}` or
  `{:error, {:parse_error, message}}`.
  """
  def parse(formula) do
    with {:ok, tokens} <- tokenize(formula),
         {:ok, ast, []} <- parse_expr(tokens) do
      {:ok, ast}
    else
      {:ok, _ast, [token | _]} ->
        {:error, {:parse_error, "unexpected #{describe_token(token)} after expression"}}

      {:error, _} = error ->
        error
    end
  end

  # --- Tokenizer ---

  defp tokenize(input), do: tokenize(input, [])

  defp tokenize("", acc), do: {:ok, Enum.reverse(acc)}

  defp tokenize(input, acc) do
    cond do
      ws = leading_match(~r/^\s+/, input) ->
        tokenize(chop(input, ws), acc)

      ref = Regex.run(@leading_ref_pattern, input) ->
        [full, type_id, concept_id, field_name] = ref
        tokenize(chop(input, full), [{:ref, {type_id, concept_id, field_name}} | acc])

      number = leading_match(~r/^\d+(?:\.\d+)?/, input) ->
        tokenize(chop(input, number), [{:number, parse_number(number)} | acc])

      ident = leading_match(~r/^[A-Za-z_]\w*/, input) ->
        tokenize(chop(input, ident), [ident_token(ident) | acc])

      op = leading_match(~r/^(?:>=|<=|==|!=|[-+*\/(),<>])/, input) ->
        tokenize(chop(input, op), [{:op, op} | acc])

      true ->
        {:error, {:parse_error, "unexpected character #{inspect(String.first(input))}"}}
    end
  end

  defp leading_match(pattern, input) do
    case Regex.run(pattern, input) do
      [match | _] -> match
      nil -> nil
    end
  end

  defp chop(input, match),
    do: binary_part(input, byte_size(match), byte_size(input) - byte_size(match))

  defp parse_number(text) do
    if String.contains?(text, "."), do: String.to_float(text), else: String.to_integer(text)
  end

  defp ident_token("true"), do: {:bool, true}
  defp ident_token("false"), do: {:bool, false}
  defp ident_token(keyword) when keyword in ~w[and or not], do: {:op, keyword}
  defp ident_token(name), do: {:ident, name}

  # --- Parser (recursive descent, lowest precedence first) ---

  defp parse_expr(tokens), do: parse_or(tokens)

  defp parse_or(tokens) do
    parse_binary_chain(tokens, &parse_and/1, ["or"], :logic)
  end

  defp parse_and(tokens) do
    parse_binary_chain(tokens, &parse_not/1, ["and"], :logic)
  end

  defp parse_not([{:op, "not"} | rest]) do
    with {:ok, operand, rest} <- parse_not(rest) do
      {:ok, {:not, operand}, rest}
    end
  end

  defp parse_not(tokens), do: parse_comparison(tokens)

  # Comparisons do not chain: `a > b > c` is a parse error (caught by the
  # unconsumed-token check in parse/1), matching mathematical usage.
  defp parse_comparison(tokens) do
    with {:ok, left, rest} <- parse_additive(tokens) do
      parse_comparison_rest(left, rest)
    end
  end

  defp parse_comparison_rest(left, [{:op, op} | rest]) when op in ~w[> < >= <= == !=] do
    with {:ok, right, rest} <- parse_additive(rest) do
      {:ok, {:compare, op, left, right}, rest}
    end
  end

  defp parse_comparison_rest(left, rest), do: {:ok, left, rest}

  defp parse_additive(tokens) do
    parse_binary_chain(tokens, &parse_multiplicative/1, ["+", "-"], :arith)
  end

  defp parse_multiplicative(tokens) do
    parse_binary_chain(tokens, &parse_unary/1, ["*", "/"], :arith)
  end

  defp parse_binary_chain(tokens, next, ops, tag) do
    with {:ok, left, rest} <- next.(tokens) do
      parse_binary_chain_rest(left, rest, {next, ops, tag})
    end
  end

  defp parse_binary_chain_rest(left, [{:op, op} | rest], {next, ops, tag} = level) do
    if op in ops do
      with {:ok, right, rest} <- next.(rest) do
        parse_binary_chain_rest({tag, op, left, right}, rest, level)
      end
    else
      {:ok, left, [{:op, op} | rest]}
    end
  end

  defp parse_binary_chain_rest(left, rest, _level), do: {:ok, left, rest}

  defp parse_unary([{:op, "-"} | rest]) do
    with {:ok, operand, rest} <- parse_unary(rest) do
      {:ok, {:negate, operand}, rest}
    end
  end

  defp parse_unary(tokens), do: parse_primary(tokens)

  defp parse_primary([{:number, n} | rest]), do: {:ok, {:number, n}, rest}
  defp parse_primary([{:bool, b} | rest]), do: {:ok, {:bool, b}, rest}
  defp parse_primary([{:ref, key} | rest]), do: {:ok, {:ref, key}, rest}

  defp parse_primary([{:ident, name}, {:op, "("} | rest]) do
    with {:ok, args, rest} <- parse_args(rest) do
      {:ok, {:call, name, args}, rest}
    end
  end

  defp parse_primary([{:ident, name} | _rest]) do
    {:error, {:parse_error, "bare identifier #{inspect(name)} is not allowed"}}
  end

  defp parse_primary([{:op, "("} | rest]) do
    with {:ok, expr, rest} <- parse_expr(rest) do
      case rest do
        [{:op, ")"} | rest] -> {:ok, expr, rest}
        _ -> {:error, {:parse_error, "missing closing parenthesis"}}
      end
    end
  end

  defp parse_primary([token | _]) do
    {:error, {:parse_error, "unexpected #{describe_token(token)}"}}
  end

  defp parse_primary([]) do
    {:error, {:parse_error, "unexpected end of formula"}}
  end

  defp parse_args([{:op, ")"} | rest]), do: {:ok, [], rest}

  defp parse_args(tokens) do
    with {:ok, arg, rest} <- parse_expr(tokens) do
      parse_args_rest(arg, rest)
    end
  end

  defp parse_args_rest(arg, [{:op, ","} | rest]) do
    with {:ok, args, rest} <- parse_args(rest) do
      {:ok, [arg | args], rest}
    end
  end

  defp parse_args_rest(arg, [{:op, ")"} | rest]), do: {:ok, [arg], rest}

  defp parse_args_rest(_arg, _rest) do
    {:error, {:parse_error, "expected ',' or ')' in argument list"}}
  end

  defp describe_token({:op, op}), do: "operator #{inspect(op)}"
  defp describe_token({:ident, name}), do: "identifier #{inspect(name)}"
  defp describe_token({:number, n}), do: "number #{n}"
  defp describe_token({:bool, b}), do: "boolean #{b}"
  defp describe_token({:ref, {t, c, f}}), do: "reference #{t}('#{c}').#{f}"

  # --- Evaluator ---

  defp eval_ast({:number, n}, _bindings), do: {:ok, n}
  defp eval_ast({:bool, b}, _bindings), do: {:ok, b}

  defp eval_ast({:ref, {type_id, concept_id, field_name} = key}, bindings) do
    case Map.fetch(bindings, key) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        {:error, {:eval_error, "unbound reference #{type_id}('#{concept_id}').#{field_name}"}}
    end
  end

  defp eval_ast({:negate, operand}, bindings) do
    with {:ok, value} <- eval_ast(operand, bindings) do
      require_number(value, "-", &{:ok, -&1})
    end
  end

  defp eval_ast({:not, operand}, bindings) do
    with {:ok, value} <- eval_ast(operand, bindings) do
      require_boolean(value, "not", &{:ok, not &1})
    end
  end

  defp eval_ast({:arith, op, left, right}, bindings) do
    with {:ok, l} <- eval_ast(left, bindings),
         {:ok, r} <- eval_ast(right, bindings) do
      apply_arithmetic(op, l, r)
    end
  end

  defp eval_ast({:logic, op, left, right}, bindings) do
    with {:ok, l} <- eval_ast(left, bindings) do
      require_boolean(l, op, fn l -> eval_logical(op, l, right, bindings) end)
    end
  end

  defp eval_ast({:compare, op, left, right}, bindings) do
    with {:ok, l} <- eval_ast(left, bindings),
         {:ok, r} <- eval_ast(right, bindings) do
      apply_comparison(op, l, r)
    end
  end

  defp eval_ast({:call, name, args}, bindings) do
    with {:ok, values} <- eval_args(args, bindings) do
      apply_function(name, values)
    end
  end

  defp eval_args(args, bindings) do
    Enum.reduce_while(args, {:ok, []}, fn arg, {:ok, acc} ->
      case eval_ast(arg, bindings) do
        {:ok, value} -> {:cont, {:ok, [value | acc]}}
        {:error, _} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, values} -> {:ok, Enum.reverse(values)}
      error -> error
    end
  end

  # `and`/`or` short-circuit like their Elixir counterparts.
  defp eval_logical("and", false, _right, _bindings), do: {:ok, false}
  defp eval_logical("or", true, _right, _bindings), do: {:ok, true}

  defp eval_logical(op, _l, right, bindings) do
    with {:ok, r} <- eval_ast(right, bindings) do
      require_boolean(r, op, &{:ok, &1})
    end
  end

  defp apply_arithmetic(op, l, r) when is_number(l) and is_number(r) do
    case op do
      "+" -> {:ok, l + r}
      "-" -> {:ok, l - r}
      "*" -> {:ok, l * r}
      "/" when r == 0 -> {:error, {:eval_error, "division by zero"}}
      "/" -> {:ok, l / r}
    end
  end

  defp apply_arithmetic(op, l, r) do
    {:error,
     {:eval_error, "#{inspect(op)} requires numbers, got: #{inspect(l)} and #{inspect(r)}"}}
  end

  defp apply_comparison(op, l, r) when is_number(l) and is_number(r) do
    case op do
      ">" -> {:ok, l > r}
      "<" -> {:ok, l < r}
      ">=" -> {:ok, l >= r}
      "<=" -> {:ok, l <= r}
      "==" -> {:ok, l == r}
      "!=" -> {:ok, l != r}
    end
  end

  defp apply_comparison(op, l, r) do
    {:error,
     {:eval_error, "#{inspect(op)} requires numbers, got: #{inspect(l)} and #{inspect(r)}"}}
  end

  defp apply_function("floor", [n]) when is_number(n), do: {:ok, floor(n)}
  defp apply_function("ceil", [n]) when is_number(n), do: {:ok, ceil(n)}
  defp apply_function("trunc", [n]) when is_number(n), do: {:ok, trunc(n)}
  defp apply_function("abs", [n]) when is_number(n), do: {:ok, abs(n)}
  defp apply_function("min", [a, b]) when is_number(a) and is_number(b), do: {:ok, min(a, b)}
  defp apply_function("max", [a, b]) when is_number(a) and is_number(b), do: {:ok, max(a, b)}

  defp apply_function(name, args) when name in ~w[floor ceil trunc abs min max] do
    {:error,
     {:eval_error, "#{name}/#{length(args)} expects numeric arguments, got: #{inspect(args)}"}}
  end

  defp apply_function(name, args) do
    {:error, {:eval_error, "unknown function #{name}/#{length(args)}"}}
  end

  defp require_number(value, _op, fun) when is_number(value), do: fun.(value)

  defp require_number(value, op, _fun) do
    {:error, {:eval_error, "#{inspect(op)} requires a number, got: #{inspect(value)}"}}
  end

  defp require_boolean(value, _op, fun) when is_boolean(value), do: fun.(value)

  defp require_boolean(value, op, _fun) do
    {:error, {:eval_error, "#{inspect(op)} requires a boolean, got: #{inspect(value)}"}}
  end
end
