defmodule ExTTRPGDev.RuleSystem.InventoryRulesTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.InventoryRules
  alias ExTTRPGDev.RuleSystem.InventoryRules.FieldSchema

  defp minimal_map do
    %{
      "inventory" => %{"inventoriable_types" => ["equipment"]},
      "inventory_item_schema" => %{
        "equipped" => %{"type" => "boolean", "default" => false},
        "condition" => %{"type" => "float", "default" => 1.0, "min" => 0.0, "max" => 1.0},
        "charges" => %{"type" => "integer", "default" => 0, "min" => 0},
        "quality" => %{
          "type" => "enum",
          "default" => "common",
          "values" => ["poor", "common", "good", "masterwork"]
        }
      }
    }
  end

  test "from_map/1 parses inventoriable_types" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert InventoryRules.inventoriable?(rules, "equipment")
    refute InventoryRules.inventoriable?(rules, "language")
  end

  test "from_map/1 parses boolean field schema" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert %FieldSchema{type: :boolean, default: false} = rules.schema["equipped"]
  end

  test "from_map/1 parses float field schema with range" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    condition = rules.schema["condition"]
    assert condition.type == :float
    assert condition.default == 1.0
    assert condition.min == 0.0
    assert condition.max == 1.0
  end

  test "from_map/1 parses integer field schema with min" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert %FieldSchema{type: :integer, default: 0, min: 0, max: nil} = rules.schema["charges"]
  end

  test "from_map/1 parses enum field schema with values" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())

    assert %FieldSchema{
             type: :enum,
             default: "common",
             values: ["poor", "common", "good", "masterwork"]
           } =
             rules.schema["quality"]
  end

  test "from_map/1 returns error for unknown field type" do
    map = %{"inventory_item_schema" => %{"foo" => %{"type" => "uuid", "default" => "abc"}}}
    assert {:error, {:unknown_field_type, "uuid"}} = InventoryRules.from_map(map)
  end

  test "from_map/1 with empty map returns empty rules" do
    assert {:ok, rules} = InventoryRules.from_map(%{})
    refute InventoryRules.inventoriable?(rules, "equipment")
    assert rules.schema == %{}
  end

  test "default_fields/1 returns map of field names to defaults" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    defaults = InventoryRules.default_fields(rules)
    assert defaults["equipped"] == false
    assert defaults["condition"] == 1.0
    assert defaults["charges"] == 0
    assert defaults["quality"] == "common"
  end
end
