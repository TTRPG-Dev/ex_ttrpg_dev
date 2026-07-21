defmodule ExTTRPGDev.RuleSystem.Loader do
  @moduledoc """
  Reads a rule system directory of TOML files and produces a unified data map
  ready for DAG construction.

  The output map has the shape:
  ```
  %{
    module: %RuleModule{},
    nodes: %{{type_id, concept_id, field_name} => %Node{}},
    rolling_methods: %{method_id => method_map},
    concept_metadata: %{{type_id, concept_id} => metadata_map},
    effects: [%Effect{}]
  }
  ```

  ## Structural Vocabulary

  The library reads the following keys from `concept_metadata` values. These are
  the library's own language for interpreting concept definitions — they are *not*
  domain names from any specific rule system, and they are fixed. Keys not in this
  list are ignored by the library (but may be used by caller code).

  ### Reserved concept type IDs

  Four concept type IDs have structural meaning to the library:

  - `"roll"` — concepts of this type define die rolling methods. Each must have
    `target_type`, `dice`, and `bonus_field` (see below).
  - `"character_progression"` — concepts of this type define character advancement
    tables. The library uses this type ID to locate progression decisions.
  - `"award"` — concepts of this type define grantable awards applied via
    `ExTTRPGDev.Characters.apply_award/4`. Keys:
    - `"value_type"` *(string, required)* — how the awarded value is obtained:
      `"integer"` (the caller must supply an integer value) or `"next_level_xp"`
      (the library computes the XP needed to reach the character's next level;
      an explicitly supplied value takes precedence).
    - `"effect_target"` *(expression string, required)* — node key expression the
      awarded value contributes to (e.g.
      `"character_trait('experience_points').total"`).
  - `"rolling_method"` — concepts of this type define how `generated` nodes are
    rolled at character generation. Keys:
    - `"name"` *(string, optional)* — display name.
    - `"dice"` *(string, required)* — dice expression rolled for the value (e.g.
      `"4d6"`).
    - `"drop"` *(string, optional)* — `"lowest"` drops the lowest die from the
      roll. No other value is supported; anything else warns at load time and is
      ignored.
    - `"default"` *(boolean, optional)* — marks this method as the system-wide
      default for `generated` nodes that do not declare a `"method"`. Exactly one
      method should set it; multiple defaults warn at load time.

  ### Universal keys (any concept type)

  - `"name"` *(string, optional)* — display name; falls back to the concept ID.

  ### Keys on `"character_progression"` concepts

  - `"type"` *(string: concept type ID, optional)* — the concept type from which
    this progression grants choices. If absent, the progression does not produce
    pending choices.
  - `"required_count"` *(formula string, optional)* — expression evaluated against
    resolved node values; result is the number of pending choices required. If
    absent, no pending choices are produced.
  - `"available_when"` *(formula string, optional)* — expression gate; if it
    evaluates to falsy the progression's choices are not surfaced to the caller.
  - `"effect_target"` *(expression string, optional)* — node key expression (e.g.
    `"character_trait('max_hit_points').points"`) where the selected concept's value
    contributes. Used for progressions whose selection directly modifies a node.
  - `"roll_reference"` *(string `"type_id.concept_id"`, optional)* — pointer to a
    `roll` concept. Resolved at evaluation time and injected as `"roll"` on the
    metadata map. Not authored directly in TOML as `"roll"`.
  - `"filter"` *(map, optional)* — filters applied when presenting options from this
    progression. All subkeys are optional:
    - `"level"` *(integer)* — exact level match; mutually exclusive with
      `"min_level"` / `"max_level_node"`.
    - `"min_level"` *(integer)* — minimum level (inclusive).
    - `"max_level_node"` *(expression string)* — expression resolving to the
      maximum allowed level.
    - `"active_in"` *(`%{"field" => string, "type" => string}`)* — restricts
      options to concepts whose `field` metadata list includes at least one active
      concept of `type`.

  ### Keys on `"roll"` concepts

  - `"target_type"` *(string: concept type ID)* — the concept type this roll
    definition targets.
  - `"dice"` *(string)* — dice expression (e.g. `"d8"`, `"2d6"`).
  - `"bonus_field"` *(string: node field name)* — the field on the target concept
    that holds the roll bonus.

  ### Keys on selectable concepts (any type eligible for selection)

  - `"level"` *(integer, optional)* — concept level used in level-range filters.
    Defaults to `0` when absent.
  - `"requires"` *(list of `%{"node" => expr, "min" => number}`, optional)* —
    prerequisites that must all be satisfied for the concept to be selectable.
    Each entry checks that `expr` evaluates to a value `>= min`.

  ### Keys on concepts with starting inventory

  - `"starting_equipment"` *(list of `%{"type" => type_id, "id" => concept_id,
    "fields" => map}`, optional)* — inventory items granted when this concept is
    selected at root scope (nil-scoped decision). `"fields"` is optional.

  ### Keys on concepts with choices

  - `"choices"` *(map: string → choice_def, optional)* — named choice definitions.
    Each value is a map with:
    - `"type"` *(string: concept type ID)* — concept type to choose from.
    - `"options"` *(list of strings, optional)* — explicit allowed concept IDs. If
      absent, all concepts of `type` satisfying the filter are eligible.
    - `"grants_to"` *(`"inventory"`, optional)* — if present, the selection creates
      an inventory item instead of a decision record.
    - `"name"` *(string, optional)* — display name for the choice prompt; falls
      back to the choice key.
    - `"contributes_field"` *(string, optional)* — field name on the selected
      concept to contribute a value to.
    - `"contributes_value"` *(any, optional)* — value contributed to
      `"contributes_field"`. Required when `"contributes_field"` is present.

  ### Note: CLI-only keys

  The following keys are consumed by `ttrpg_dev_cli`, not by this library:

  - `"hidden"` *(boolean, optional)* — omits the concept from character sheet
    display. Has no effect on DAG evaluation.
  """

  require Logger

  alias ExTTRPGDev.RuleSystem.{Effect, Expression, InventoryRules, Node, RuleModule, Vocabulary}

  @module_file "module.toml"
  @character_building_file "character_building.toml"
  @inventory_rules_file "inventory_rules.toml"

  # Bound to attributes at compile time; the names are owned by
  # ExTTRPGDev.RuleSystem.Vocabulary. The MapSet is bound here rather than
  # fetched per-call because dialyzer loses MapSet's opaqueness across the
  # module boundary and rejects the cross-module value in MapSet.union/2.
  @rolling_method_type Vocabulary.rolling_method_type()
  @structural_metadata_keys MapSet.new(Vocabulary.structural_metadata_keys())

  @doc "Loads a rule system directory, returning `{:ok, data}` or `{:error, reason}`."
  def load(path) do
    with {:ok, rule_module} <- load_module(path),
         {:ok, data} <- load_concept_files(path, rule_module),
         {:ok, inventory_rules} <- load_inventory_rules(path) do
      data = expand_metadata_contributions(data, rule_module)
      warn_unknown_metadata_keys(data.concept_metadata, rule_module, inventory_rules)
      warn_rolling_method_issues(data)
      {:ok, data |> Map.put(:module, rule_module) |> Map.put(:inventory_rules, inventory_rules)}
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
    with {:ok, rule_module} <- parse_module_file(path),
         {:ok, choices} <- load_character_building_choices(path) do
      {:ok, %{rule_module | character_building_choices: choices}}
    end
  end

  defp parse_module_file(path) do
    module_path = Path.join(path, @module_file)

    with {:ok, contents} <- File.read(module_path),
         {:ok, map} <- TomlElixir.decode(contents),
         {:ok, rule_module} <- RuleModule.from_map(map) do
      {:ok, rule_module}
    else
      {:error, reason} -> {:error, {:module_parse_error, reason}}
    end
  end

  # A missing file is fine (the system has no inventory rules); any other
  # failure — unreadable file, TOML syntax error, validation error from
  # InventoryRules.from_map — must surface, not silently yield an empty
  # default.
  defp load_inventory_rules(path) do
    rules_path = Path.join(path, @inventory_rules_file)

    case File.read(rules_path) do
      {:error, :enoent} ->
        {:ok, %InventoryRules{}}

      {:error, reason} ->
        {:error, {:inventory_rules_error, reason}}

      {:ok, contents} ->
        with {:ok, map} <- TomlElixir.decode(contents),
             {:ok, rules} <- InventoryRules.from_map(map) do
          {:ok, rules}
        else
          {:error, reason} -> {:error, {:inventory_rules_error, reason}}
        end
    end
  end

  # Same policy as load_inventory_rules: only a missing file falls back.
  defp load_character_building_choices(path) do
    building_path = Path.join(path, @character_building_file)

    case File.read(building_path) do
      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, {:character_building_error, reason}}

      {:ok, contents} ->
        case TomlElixir.decode(contents) do
          {:ok, map} -> {:ok, parse_character_choices(map)}
          {:error, reason} -> {:error, {:character_building_error, reason}}
        end
    end
  end

  defp parse_character_choices(map) do
    map
    |> Map.get("character_choice", [])
    |> Enum.map(fn cc ->
      %RuleModule.CharacterChoice{
        concept_type: cc["concept_type"],
        required: Map.get(cc, "required", true)
      }
    end)
  end

  defp load_concept_files(path, rule_module) do
    type_ids = RuleModule.concept_type_ids(rule_module)

    initial = %{nodes: %{}, rolling_methods: %{}, concept_metadata: %{}, effects: []}

    path
    |> Path.join("concepts/**/*.toml")
    |> Path.wildcard()
    |> Enum.reduce_while({:ok, initial}, fn file_path, {:ok, acc} ->
      with {:ok, contents} <- File.read(file_path),
           {:ok, toml_map} <- TomlElixir.decode(contents) do
        {:cont, {:ok, process_toml_map(toml_map, acc, type_ids)}}
      else
        {:error, reason} -> {:halt, {:error, {:file_parse_error, file_path, reason}}}
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

  defp process_type(@rolling_method_type, concepts, acc) do
    rolling_methods =
      Enum.reduce(concepts, acc.rolling_methods, fn {id, fields}, rm ->
        method = parse_rolling_method(fields)

        if is_nil(method.dice) do
          Logger.warning("Rolling method #{inspect(id)} is missing required field \"dice\".")
        end

        Map.put(rm, id, method)
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
            value
            |> Enum.map(&parse_effect({type_id, concept_id}, &1))
            |> Enum.reject(&is_nil/1)

          {nodes, Map.put(meta, field_name, value), effects ++ new_effects}

        is_map(value) and (Map.has_key?(value, "type") or Map.has_key?(value, "formula")) ->
          {add_parsed_node(nodes, {type_id, concept_id, field_name}, value), meta, effects}

        true ->
          {nodes, Map.put(meta, field_name, value), effects}
      end
    end)
  end

  defp add_parsed_node(nodes, node_key, value) do
    case parse_node(value) do
      nil ->
        warn_unknown_node_type(value, node_key)
        nodes

      node ->
        warn_missing_node_fields(node, node_key)
        Map.put(nodes, node_key, node)
    end
  end

  defp parse_node(%{"type" => "generated"} = map) do
    %Node{type: :generated, method: Map.get(map, "method")}
  end

  defp parse_node(%{"type" => "accumulator"} = map) do
    %Node{type: :accumulator, base: Map.get(map, "base")}
  end

  defp parse_node(%{"type" => "mapping"} = map) do
    %Node{type: :mapping, input: Map.get(map, "input"), steps: Map.get(map, "steps")}
  end

  defp parse_node(%{"formula" => formula}) do
    %Node{type: :formula, formula: formula}
  end

  # Unrecognized node definition (e.g. a typo'd "type" value with no
  # "formula" key). The caller warns and skips the node instead of this
  # clause head raising FunctionClauseError.
  defp parse_node(_), do: nil

  defp warn_unknown_node_type(value, {type_id, concept_id, field}) do
    Logger.warning(
      "Node #{inspect(field)} on #{inspect(type_id)} concept #{inspect(concept_id)} " <>
        "has unrecognized type #{inspect(value["type"])}; expected \"generated\", " <>
        "\"accumulator\", \"mapping\", or a \"formula\" key. Node skipped."
    )
  end

  defp warn_missing_node_fields(%Node{type: :mapping} = node, {type_id, concept_id, field}) do
    for {key, label} <- [{:input, "input"}, {:steps, "steps"}],
        is_nil(Map.get(node, key)) do
      Logger.warning(
        "Node #{inspect(field)} on #{inspect(type_id)} concept #{inspect(concept_id)} " <>
          "has type :mapping but is missing required field #{inspect(label)}."
      )
    end
  end

  defp warn_missing_node_fields(_, _), do: :ok

  # Runs after all concept files are loaded, because a generated node may
  # legitimately rely on a default rolling method defined in a different file.
  defp warn_rolling_method_issues(%{nodes: nodes, rolling_methods: methods}) do
    default_ids = for {id, method} <- methods, method.default, do: id

    if length(default_ids) > 1 do
      Logger.warning(
        "Multiple rolling methods declare default = true: " <>
          "#{default_ids |> Enum.sort() |> Enum.join(", ")}. The default is ambiguous."
      )
    end

    for {id, %{drop: drop}} <- methods, not is_nil(drop) and drop != "lowest" do
      Logger.warning(
        "Rolling method #{inspect(id)} has unsupported drop value #{inspect(drop)}; " <>
          "only \"lowest\" is supported. The drop will be ignored."
      )
    end

    for {node_key, %Node{type: :generated, method: method_id}} <- nodes do
      warn_generated_method_issue(node_key, method_id, methods, default_ids)
    end

    :ok
  end

  defp warn_generated_method_issue({type_id, concept_id, field}, nil, _methods, []) do
    Logger.warning(
      "Node #{inspect(field)} on #{inspect(type_id)} concept #{inspect(concept_id)} " <>
        "has type :generated with no \"method\", and no rolling method declares " <>
        "default = true."
    )
  end

  defp warn_generated_method_issue({type_id, concept_id, field}, method_id, methods, _defaults)
       when not is_nil(method_id) do
    unless Map.has_key?(methods, method_id) do
      Logger.warning(
        "Node #{inspect(field)} on #{inspect(type_id)} concept #{inspect(concept_id)} " <>
          "references unknown rolling method #{inspect(method_id)}."
      )
    end
  end

  defp warn_generated_method_issue(_node_key, _method_id, _methods, _defaults), do: :ok

  defp parse_rolling_method(fields) do
    %{
      name: fields["name"],
      dice: fields["dice"],
      drop: fields["drop"],
      default: Map.get(fields, "default", false)
    }
  end

  defp expand_metadata_contributions(data, rule_module) do
    new_effects =
      Enum.flat_map(rule_module.metadata_contributions, fn contribution ->
        expand_contribution(data.concept_metadata, contribution)
      end)

    %{data | effects: data.effects ++ new_effects}
  end

  defp expand_contribution(concept_metadata, contribution) do
    concept_metadata
    |> Enum.filter(fn {{type, _id}, _meta} -> type == contribution.from_type end)
    |> Enum.flat_map(fn {{_type, source_id}, meta} ->
      expand_source_values(concept_metadata, contribution, source_id, meta)
    end)
  end

  defp expand_source_values(concept_metadata, contribution, source_id, meta) do
    # List.wrap: a scalar value (`languages = "Common"`) is treated as a
    # single-element list instead of crashing the flat_map.
    values = meta |> Map.get(contribution.from_field) |> List.wrap()

    Enum.flat_map(values, fn val ->
      targets = find_contribution_targets(concept_metadata, contribution, val)

      Enum.map(targets, fn target_id ->
        %Effect{
          source: {contribution.from_type, source_id},
          target: {contribution.to_type, target_id, contribution.to_field},
          value: contribution.value,
          when: nil
        }
      end)
    end)
  end

  defp find_contribution_targets(concept_metadata, contribution, val) do
    case Enum.find(contribution.label_filters, fn lf -> lf.label == val end) do
      %{filter_field: filter_field, filter_value: filter_value} ->
        concept_metadata
        |> Enum.filter(fn {{type, _id}, meta} ->
          type == contribution.to_type and Map.get(meta, filter_field) == filter_value
        end)
        |> Enum.map(fn {{_type, id}, _meta} -> id end)

      nil ->
        concept_metadata
        |> Enum.filter(fn {{type, id}, meta} ->
          type == contribution.to_type and (id == val or Map.get(meta, "name") == val)
        end)
        |> Enum.map(fn {{_type, id}, _meta} -> id end)
    end
  end

  defp warn_unknown_metadata_keys(concept_metadata, rule_module, inventory_rules) do
    allowed = build_allowed_keys(rule_module, inventory_rules)

    concept_metadata
    |> Enum.flat_map(fn {{type_id, concept_id}, meta} ->
      meta
      |> Map.keys()
      |> Enum.reject(&MapSet.member?(allowed, &1))
      |> Enum.map(&{&1, type_id, concept_id})
    end)
    |> Enum.group_by(fn {key, type_id, _concept_id} -> {key, type_id} end)
    |> Enum.sort_by(fn {{key, type_id}, _} -> {type_id, key} end)
    |> Enum.each(fn {{key, type_id}, instances} ->
      ids = instances |> Enum.map(fn {_, _, id} -> id end) |> Enum.sort()
      {shown, rest} = Enum.split(ids, 5)
      id_str = Enum.join(shown, ", ") <> if(rest == [], do: "", else: " and #{length(rest)} more")
      count = length(ids)
      noun = if count == 1, do: "concept", else: "concepts"

      Logger.warning(
        "Unknown metadata key #{inspect(key)} on #{count} #{inspect(type_id)} #{noun} " <>
          "in system #{inspect(rule_module.slug)}: #{id_str}. " <>
          "If intentional, add #{inspect(key)} to custom_metadata_keys in module.toml. " <>
          "See ExTTRPGDev.RuleSystem.Loader for the structural vocabulary."
      )
    end)
  end

  defp build_allowed_keys(rule_module, inventory_rules) do
    from_contributions =
      Enum.flat_map(rule_module.metadata_contributions, fn mc ->
        [mc.from_field | Enum.map(mc.label_filters, & &1.filter_field)]
      end)

    [
      from_contributions,
      rule_module.custom_metadata_keys,
      extract_inventory_rules_keys(inventory_rules)
    ]
    |> Enum.concat()
    |> MapSet.new()
    |> MapSet.union(@structural_metadata_keys)
  end

  defp extract_inventory_rules_keys(%InventoryRules{types: nil}), do: []

  defp extract_inventory_rules_keys(%InventoryRules{types: types}) do
    Enum.flat_map(types, fn {_type_id, config} ->
      case config.preparation do
        nil ->
          []

        prep ->
          base = [prep.mode_field, prep.pool_field, prep.always_prepared_metadata_key]
          pool_keys = (prep.pools || %{}) |> Map.values() |> Enum.map(& &1.class_filter_field)
          Enum.filter(base ++ pool_keys, & &1)
      end
    end)
  end

  defp parse_effect(source, %{"target" => target, "value" => value} = entry) do
    case Expression.parse_ref(target) do
      {:ok, ref} ->
        %Effect{
          source: source,
          target: ref,
          value: value,
          when: Map.get(entry, "when")
        }

      :error ->
        {source_type, source_id} = source

        Logger.warning(
          "Contribution on #{inspect(source_type)} concept #{inspect(source_id)} has " <>
            "unparseable target #{inspect(target)}; expected \"type('id').field\". " <>
            "Effect skipped."
        )

        nil
    end
  end

  defp parse_effect({source_type, source_id}, entry) do
    Logger.warning(
      "Contribution on #{inspect(source_type)} concept #{inspect(source_id)} is missing " <>
        "required key(s) \"target\" and/or \"value\": #{inspect(entry)}. Effect skipped."
    )

    nil
  end
end
