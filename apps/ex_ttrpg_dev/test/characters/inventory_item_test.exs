defmodule ExTTRPGDev.Characters.InventoryItemTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters.InventoryItem
  alias ExTTRPGDev.RuleSystem.InventoryRules

  defp rules do
    {:ok, rules} =
      InventoryRules.from_map(%{
        "inventory_type" => %{
          "equipment" => %{
            "activate_command" => "equip",
            "activation_field" => "equipped",
            "schema" => %{
              "equipped" => %{"type" => "boolean", "default" => false},
              "condition" => %{"type" => "float", "default" => 1.0, "min" => 0.0, "max" => 1.0}
            }
          }
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

  defp rules_with_int_and_enum do
    {:ok, rules} =
      InventoryRules.from_map(%{
        "inventory_type" => %{
          "equipment" => %{
            "schema" => %{
              "charges" => %{"type" => "integer", "default" => 3, "min" => 0, "max" => 10},
              "quality" => %{
                "type" => "enum",
                "default" => "common",
                "values" => ["poor", "common", "good"]
              }
            }
          }
        }
      })

    rules
  end

  test "new/4 creates item with integer and enum field defaults" do
    assert {:ok, item} = InventoryItem.new("equipment", "longsword", rules_with_int_and_enum())
    assert item.fields["charges"] == 3
    assert item.fields["quality"] == "common"
  end

  test "new/4 returns error for invalid integer type" do
    assert {:error, {:invalid_type, :integer}} =
             InventoryItem.new("equipment", "longsword", rules_with_int_and_enum(), %{
               "charges" => 3.5
             })
  end

  test "new/4 returns error for integer value above maximum" do
    assert {:error, {:above_maximum, 11, 10}} =
             InventoryItem.new("equipment", "longsword", rules_with_int_and_enum(), %{
               "charges" => 11
             })
  end

  test "new/4 accepts a valid enum value" do
    assert {:ok, item} =
             InventoryItem.new("equipment", "longsword", rules_with_int_and_enum(), %{
               "quality" => "good"
             })

    assert item.fields["quality"] == "good"
  end

  test "new/4 returns error for invalid enum value" do
    assert {:error, {:invalid_enum_value, "legendary", _}} =
             InventoryItem.new("equipment", "longsword", rules_with_int_and_enum(), %{
               "quality" => "legendary"
             })
  end

  test "new/4 returns error for invalid enum type" do
    assert {:error, {:invalid_type, :enum}} =
             InventoryItem.new("equipment", "longsword", rules_with_int_and_enum(), %{
               "quality" => 42
             })
  end

  test "set_field/4 returns error for value below minimum" do
    {:ok, item} = InventoryItem.new("equipment", "longsword", rules())

    assert {:error, {:below_minimum, val, min}} =
             InventoryItem.set_field(item, "condition", -0.1, rules())

    assert val == -0.1
    assert min == 0.0
  end
end
