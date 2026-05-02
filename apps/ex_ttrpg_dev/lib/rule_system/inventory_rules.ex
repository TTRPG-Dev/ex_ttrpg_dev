defmodule ExTTRPGDev.RuleSystem.InventoryRules do
  @moduledoc """
  Parsed inventory rules for a rule system, loaded from `inventory_rules.toml`.

  Defines typed inventories, each with its own field schema, activation verbs, and
  optional preparation config. A character can hold items of any declared inventory
  type. The inventory type id matches the concept type that populates it (e.g.
  `"equipment"`, `"spell"`).

  If a rule system has no `inventory_rules.toml`, an empty `InventoryRules` is
  used — no concept types are inventoriable.
  """

  defmodule FieldSchema do
    @moduledoc "Schema definition for a single inventory item instance field."
    defstruct [:name, :type, :default, :min, :max, :values]
  end

  defmodule ProgressionConfig do
    @moduledoc """
    Config for a `character_progression` that feeds resolved selections into an
    inventory type automatically (via the `resolve_choice` hook).
    """
    defstruct [:progression, auto_activate: false, excludes_from_cap: false]
  end

  defmodule PoolConfig do
    @moduledoc "Config for one eligible preparation pool (e.g. class_spells or spellbook)."
    defstruct [:class_filter_field, :scope_type, :scope_id, :management]
  end

  defmodule PreparationConfig do
    @moduledoc """
    Config for preparation-managed inventory types (e.g. spell inventory).

    Drives `Characters.activate/4`: eligible-pool computation, cap enforcement,
    always-prepared resolution, and auto-activation for all-known classes.
    """
    defstruct [
      :mode_field,
      :activation_mode,
      :pool_field,
      :cap_field,
      :level_field,
      :max_level_node,
      :always_prepared_subclass_choice,
      :always_prepared_metadata_key,
      :auto_activate_when_field,
      :auto_activate_when_value,
      pools: %{}
    ]
  end

  defmodule TypeConfig do
    @moduledoc "Configuration for a single typed inventory."
    defstruct [
      :activate_command,
      :deactivate_command,
      :activation_field,
      schema: %{},
      add_on_progression: [],
      preparation: nil
    ]
  end

  defstruct types: %{}

  @doc """
  Builds an `InventoryRules` struct from a decoded TOML map.

  Returns `{:ok, %InventoryRules{}}` or `{:error, reason}`.
  """
  def from_map(map) do
    types_map = Map.get(map, "inventory_type", %{})

    result =
      Enum.reduce(types_map, {:ok, %{}}, fn
        {type_id, type_map}, {:ok, acc} ->
          case parse_type_config(type_map) do
            {:ok, config} -> {:ok, Map.put(acc, type_id, config)}
            error -> error
          end

        _, error ->
          error
      end)

    case result do
      {:ok, types} -> {:ok, %__MODULE__{types: types}}
      error -> error
    end
  end

  @doc "Returns true if the given concept type can appear in any inventory."
  def inventoriable?(%__MODULE__{types: types}, concept_type) do
    Map.has_key?(types, concept_type)
  end

  @doc "Returns default field values for items of the given inventory type."
  def default_fields(%__MODULE__{types: types}, type_id) do
    case Map.fetch(types, type_id) do
      {:ok, %TypeConfig{schema: schema}} ->
        Map.new(schema, fn {name, field_schema} -> {name, field_schema.default} end)

      :error ->
        %{}
    end
  end

  @doc "Returns the field schema map for a given inventory type."
  def type_schema(%__MODULE__{types: types}, type_id) do
    case Map.fetch(types, type_id) do
      {:ok, %TypeConfig{schema: schema}} -> schema
      :error -> %{}
    end
  end

  @doc "Returns the `TypeConfig` for a given type id, or `nil` if not found."
  def type_config(%__MODULE__{types: types}, type_id) do
    Map.get(types, type_id)
  end

  @doc """
  Returns `{type_id, TypeConfig}` for the type whose `activate_command` or
  `deactivate_command` matches `verb`, or `nil` if not found.
  """
  def type_for_activate_command(%__MODULE__{types: types}, verb) do
    Enum.find_value(types, fn {type_id, config} ->
      if config.activate_command == verb or config.deactivate_command == verb do
        {type_id, config}
      end
    end)
  end

  @doc """
  Returns the `ProgressionConfig` for the given progression id within an inventory
  type, or `nil` if the progression does not feed that type.
  """
  def progression_config(%__MODULE__{types: types}, type_id, progression_id) do
    case Map.fetch(types, type_id) do
      {:ok, %TypeConfig{add_on_progression: progressions}} ->
        Enum.find(progressions, &(&1.progression == progression_id))

      :error ->
        nil
    end
  end

  @doc """
  Returns `{type_id, ProgressionConfig}` for the inventory type that the given
  progression feeds into, or `nil` if none.
  """
  def type_for_progression(%__MODULE__{types: types}, progression_id) do
    Enum.find_value(types, fn {type_id, %TypeConfig{add_on_progression: progressions}} ->
      prog = Enum.find(progressions, &(&1.progression == progression_id))
      if prog, do: {type_id, prog}
    end)
  end

  @doc "Returns all `{type_id, TypeConfig}` pairs that have a preparation config."
  def preparation_types(%__MODULE__{types: types}) do
    Enum.filter(types, fn {_id, config} -> config.preparation != nil end)
  end

  # --- Parsing ---

  defp parse_type_config(type_map) do
    with {:ok, schema} <- parse_schema(Map.get(type_map, "schema", %{})),
         {:ok, preparation} <- parse_preparation(Map.get(type_map, "preparation")) do
      {:ok,
       %TypeConfig{
         activate_command: type_map["activate_command"],
         deactivate_command: type_map["deactivate_command"],
         activation_field: type_map["activation_field"],
         schema: schema,
         add_on_progression: parse_progressions(Map.get(type_map, "add_on_progression", [])),
         preparation: preparation
       }}
    end
  end

  defp parse_schema(schema_map) do
    Enum.reduce(schema_map, {:ok, %{}}, fn
      {field_name, field_map}, {:ok, acc} ->
        case parse_field_schema(field_name, field_map) do
          {:ok, field_schema} -> {:ok, Map.put(acc, field_name, field_schema)}
          error -> error
        end

      _, error ->
        error
    end)
  end

  defp parse_progressions(list) do
    Enum.map(list, fn prog_map ->
      %ProgressionConfig{
        progression: prog_map["progression"],
        auto_activate: Map.get(prog_map, "auto_activate", false),
        excludes_from_cap: Map.get(prog_map, "excludes_from_cap", false)
      }
    end)
  end

  defp parse_preparation(nil), do: {:ok, nil}

  defp parse_preparation(prep_map) do
    pools =
      (prep_map["pool"] || %{})
      |> Map.new(fn {pool_name, pool_map} ->
        {pool_name,
         %PoolConfig{
           class_filter_field: pool_map["class_filter_field"],
           scope_type: pool_map["scope_type"],
           scope_id: pool_map["scope_id"],
           management: pool_map["management"]
         }}
      end)

    always = prep_map["always_prepared"] || %{}
    auto_when = prep_map["auto_activate_when"] || %{}

    max_level_node =
      case prep_map["max_level_node"] do
        [type_id, concept_id, field] -> {type_id, concept_id, field}
        _ -> nil
      end

    {:ok,
     %PreparationConfig{
       mode_field: prep_map["mode_field"],
       activation_mode: prep_map["activation_mode"],
       pool_field: prep_map["pool_field"],
       cap_field: prep_map["cap_field"],
       level_field: prep_map["level_field"],
       max_level_node: max_level_node,
       always_prepared_subclass_choice: always["subclass_choice"],
       always_prepared_metadata_key: always["metadata_key"],
       auto_activate_when_field: auto_when["class_field"],
       auto_activate_when_value: auto_when["class_value"],
       pools: pools
     }}
  end

  defp parse_field_schema(name, map) do
    case parse_type(map["type"]) do
      {:ok, type} ->
        {:ok,
         %FieldSchema{
           name: name,
           type: type,
           default: map["default"],
           min: map["min"],
           max: map["max"],
           values: map["values"]
         }}

      error ->
        error
    end
  end

  defp parse_type("boolean"), do: {:ok, :boolean}
  defp parse_type("float"), do: {:ok, :float}
  defp parse_type("integer"), do: {:ok, :integer}
  defp parse_type("enum"), do: {:ok, :enum}
  defp parse_type(other), do: {:error, {:unknown_field_type, other}}
end
