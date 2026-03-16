defmodule ExTTRPGDev.Characters.InventoryItem do
  @moduledoc """
  An instance of an inventoriable concept in a character's inventory.

  Holds a reference to a concept (by type and id) and a map of instance fields
  as defined by the rule system's `inventory_rules.toml`. Field values are
  validated against the schema when creating or updating items.
  """

  alias ExTTRPGDev.RuleSystem.InventoryRules
  alias ExTTRPGDev.RuleSystem.InventoryRules.FieldSchema

  defstruct [:concept_type, :concept_id, :fields]

  @doc """
  Creates a new `InventoryItem`, merging defaults with any provided fields and
  validating against the system's inventory rules.

  Returns `{:ok, %InventoryItem{}}` or `{:error, reason}`.
  """
  def new(concept_type, concept_id, %InventoryRules{} = inventory_rules, custom_fields \\ %{}) do
    if InventoryRules.inventoriable?(inventory_rules, concept_type) do
      fields = Map.merge(InventoryRules.default_fields(inventory_rules), custom_fields)

      case validate_fields(fields, inventory_rules.schema) do
        :ok ->
          {:ok, %__MODULE__{concept_type: concept_type, concept_id: concept_id, fields: fields}}

        error ->
          error
      end
    else
      {:error, {:not_inventoriable, concept_type}}
    end
  end

  @doc """
  Updates a single field value on an inventory item, validating against the schema.

  Returns `{:ok, updated_item}` or `{:error, reason}`.
  """
  def set_field(%__MODULE__{} = item, field_name, value, %InventoryRules{} = inventory_rules) do
    case Map.fetch(inventory_rules.schema, field_name) do
      {:ok, schema} ->
        case validate_field_value(value, schema) do
          :ok -> {:ok, %{item | fields: Map.put(item.fields, field_name, value)}}
          error -> error
        end

      :error ->
        {:error, {:unknown_field, field_name}}
    end
  end

  defp validate_fields(fields, schema) do
    Enum.reduce_while(fields, :ok, &validate_field_entry(&1, &2, schema))
  end

  defp validate_field_entry({name, value}, :ok, schema) do
    with {:ok, field_schema} <- fetch_schema_field(schema, name),
         :ok <- validate_field_value(value, field_schema) do
      {:cont, :ok}
    else
      error -> {:halt, error}
    end
  end

  defp fetch_schema_field(schema, name) do
    case Map.fetch(schema, name) do
      {:ok, _} = ok -> ok
      :error -> {:error, {:unknown_field, name}}
    end
  end

  defp validate_field_value(value, %FieldSchema{type: :boolean}) when is_boolean(value), do: :ok

  defp validate_field_value(_, %FieldSchema{type: :boolean}),
    do: {:error, {:invalid_type, :boolean}}

  defp validate_field_value(value, %FieldSchema{type: :float} = schema)
       when is_float(value) or is_integer(value),
       do: validate_range(value * 1.0, schema)

  defp validate_field_value(_, %FieldSchema{type: :float}), do: {:error, {:invalid_type, :float}}

  defp validate_field_value(value, %FieldSchema{type: :integer} = schema) when is_integer(value),
    do: validate_range(value, schema)

  defp validate_field_value(_, %FieldSchema{type: :integer}),
    do: {:error, {:invalid_type, :integer}}

  defp validate_field_value(value, %FieldSchema{type: :enum, values: values})
       when is_binary(value) do
    if value in values, do: :ok, else: {:error, {:invalid_enum_value, value, values}}
  end

  defp validate_field_value(_, %FieldSchema{type: :enum}), do: {:error, {:invalid_type, :enum}}

  defp validate_range(value, %FieldSchema{min: min}) when is_number(min) and value < min,
    do: {:error, {:below_minimum, value, min}}

  defp validate_range(value, %FieldSchema{max: max}) when is_number(max) and value > max,
    do: {:error, {:above_maximum, value, max}}

  defp validate_range(_, _), do: :ok
end
