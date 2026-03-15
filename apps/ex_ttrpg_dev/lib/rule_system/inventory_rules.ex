defmodule ExTTRPGDev.RuleSystem.InventoryRules do
  @moduledoc """
  Parsed inventory rules for a rule system, loaded from `inventory_rules.toml`.

  Defines which concept types can appear in a character's inventory and the
  schema for instance fields on inventory items (e.g., `equipped`, `condition`).

  If a rule system has no `inventory_rules.toml`, an empty `InventoryRules` is
  used — no concept types are inventoriable and items have no instance fields.
  """

  defmodule FieldSchema do
    @moduledoc "Schema definition for a single inventory item instance field."
    defstruct [:name, :type, :default, :min, :max, :values]
  end

  defstruct inventoriable_types: MapSet.new(), schema: %{}

  @doc """
  Builds an `InventoryRules` struct from a decoded TOML map.

  Returns `{:ok, %InventoryRules{}}` or `{:error, reason}`.
  """
  def from_map(map) do
    inventoriable_types =
      map
      |> Map.get("inventory", %{})
      |> Map.get("inventoriable_types", [])
      |> MapSet.new()

    schema =
      map
      |> Map.get("inventory_item_schema", %{})
      |> Enum.reduce({:ok, %{}}, fn
        {field_name, field_map}, {:ok, acc} ->
          case parse_field_schema(field_name, field_map) do
            {:ok, field_schema} -> {:ok, Map.put(acc, field_name, field_schema)}
            error -> error
          end

        _, error ->
          error
      end)

    case schema do
      {:ok, parsed_schema} ->
        {:ok, %__MODULE__{inventoriable_types: inventoriable_types, schema: parsed_schema}}

      error ->
        error
    end
  end

  @doc "Returns true if the given concept type can be added to inventory."
  def inventoriable?(%__MODULE__{inventoriable_types: types}, concept_type) do
    MapSet.member?(types, concept_type)
  end

  @doc "Returns default field values for a new inventory item."
  def default_fields(%__MODULE__{schema: schema}) do
    Map.new(schema, fn {name, field_schema} -> {name, field_schema.default} end)
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
