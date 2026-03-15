defmodule ExTTRPGDev.Characters.InventoryItemTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters.InventoryItem
  alias ExTTRPGDev.RuleSystem.InventoryRules

  defp rules do
    {:ok, rules} =
      InventoryRules.from_map(%{
        "inventory" => %{"inventoriable_types" => ["equipment"]},
        "inventory_item_schema" => %{
          "equipped" => %{"type" => "boolean", "default" => false},
          "condition" => %{"type" => "float", "default" => 1.0, "min" => 0.0, "max" => 1.0}
        }
      })

    rules
  end

  test "new/4 creates item with default fields" do
    assert {:ok, item} = InventoryItem.new("equipment", "longsword", rules())
    assert item.concept_type == "equipment"
    assert item.concept_id == "longsword"
    assert item.fields["equipped"] == false
    assert item.fields["condition"] == 1.0
  end

  test "new/4 merges custom fields over defaults" do
    assert {:ok, item} =
             InventoryItem.new("equipment", "longsword", rules(), %{"equipped" => true})

    assert item.fields["equipped"] == true
    assert item.fields["condition"] == 1.0
  end

  test "new/4 returns error for non-inventoriable concept type" do
    assert {:error, {:not_inventoriable, "language"}} =
             InventoryItem.new("language", "common", rules())
  end

  test "new/4 returns error when custom field value fails type validation" do
    assert {:error, {:invalid_type, :boolean}} =
             InventoryItem.new("equipment", "longsword", rules(), %{"equipped" => "yes"})
  end

  test "new/4 returns error when custom field value is out of range" do
    assert {:error, {:above_maximum, 1.5, 1.0}} =
             InventoryItem.new("equipment", "longsword", rules(), %{"condition" => 1.5})
  end

  test "new/4 returns error for unknown field in custom fields" do
    assert {:error, {:unknown_field, "durability"}} =
             InventoryItem.new("equipment", "longsword", rules(), %{"durability" => 100})
  end

  test "set_field/4 updates a valid field value" do
    {:ok, item} = InventoryItem.new("equipment", "longsword", rules())
    assert {:ok, updated} = InventoryItem.set_field(item, "equipped", true, rules())
    assert updated.fields["equipped"] == true
  end

  test "set_field/4 returns error for unknown field" do
    {:ok, item} = InventoryItem.new("equipment", "longsword", rules())

    assert {:error, {:unknown_field, "durability"}} =
             InventoryItem.set_field(item, "durability", 5, rules())
  end

  test "set_field/4 returns error for type mismatch" do
    {:ok, item} = InventoryItem.new("equipment", "longsword", rules())

    assert {:error, {:invalid_type, :boolean}} =
             InventoryItem.set_field(item, "equipped", 1, rules())
  end

  test "set_field/4 returns error for value below minimum" do
    {:ok, item} = InventoryItem.new("equipment", "longsword", rules())

    assert {:error, {:below_minimum, val, min}} =
             InventoryItem.set_field(item, "condition", -0.1, rules())

    assert val == -0.1
    assert min == 0.0
  end
end
