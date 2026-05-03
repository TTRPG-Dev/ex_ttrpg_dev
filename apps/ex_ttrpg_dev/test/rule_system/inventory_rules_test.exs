defmodule ExTTRPGDev.RuleSystem.InventoryRulesTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.InventoryRules
  alias ExTTRPGDev.RuleSystem.InventoryRules.FieldSchema

  defp minimal_map do
    %{
      "inventory_type" => %{
        "equipment" => %{
          "activate_command" => "equip",
          "deactivate_command" => "unequip",
          "activation_field" => "equipped",
          "schema" => %{
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
      }
    }
  end

  test "from_map/1 parses inventoriable types" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert InventoryRules.inventoriable?(rules, "equipment")
    refute InventoryRules.inventoriable?(rules, "language")
  end

  test "from_map/1 parses boolean field schema" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())

    assert %FieldSchema{type: :boolean, default: false} =
             rules.types["equipment"].schema["equipped"]
  end

  test "from_map/1 parses float field schema with range" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())

    assert %FieldSchema{type: :float, default: 1.0, min: 0.0, max: 1.0} =
             rules.types["equipment"].schema["condition"]
  end

  test "from_map/1 parses integer field schema with min" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())

    assert %FieldSchema{type: :integer, default: 0, min: 0, max: nil} =
             rules.types["equipment"].schema["charges"]
  end

  test "from_map/1 parses enum field schema with values" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())

    assert %FieldSchema{
             type: :enum,
             default: "common",
             values: ["poor", "common", "good", "masterwork"]
           } = rules.types["equipment"].schema["quality"]
  end

  test "from_map/1 returns error for unknown field type" do
    map = %{
      "inventory_type" => %{
        "equipment" => %{"schema" => %{"foo" => %{"type" => "uuid", "default" => "abc"}}}
      }
    }

    assert {:error, {:unknown_field_type, "uuid"}} = InventoryRules.from_map(map)
  end

  test "from_map/1 short-circuits on first field error when multiple fields are invalid" do
    map = %{
      "inventory_type" => %{
        "equipment" => %{
          "schema" => %{
            "foo" => %{"type" => "uuid", "default" => ""},
            "bar" => %{"type" => "xml", "default" => ""}
          }
        }
      }
    }

    assert {:error, {:unknown_field_type, _}} = InventoryRules.from_map(map)
  end

  test "from_map/1 with empty map returns empty rules" do
    assert {:ok, rules} = InventoryRules.from_map(%{})
    refute InventoryRules.inventoriable?(rules, "equipment")
  end

  test "default_fields/2 returns map of field names to defaults for a type" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())

    assert InventoryRules.default_fields(rules, "equipment") == %{
             "equipped" => false,
             "condition" => 1.0,
             "charges" => 0,
             "quality" => "common"
           }
  end

  test "default_fields/2 returns empty map for unknown type" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert InventoryRules.default_fields(rules, "spell") == %{}
  end

  test "type_schema/2 returns schema for a type" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    schema = InventoryRules.type_schema(rules, "equipment")
    assert map_size(schema) == 4
    assert schema["equipped"].type == :boolean
  end

  test "type_schema/2 returns empty map for unknown type" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert InventoryRules.type_schema(rules, "spell") == %{}
  end

  test "type_config/2 returns TypeConfig for a known type" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())

    assert %InventoryRules.TypeConfig{
             activate_command: "equip",
             deactivate_command: "unequip",
             activation_field: "equipped"
           } = InventoryRules.type_config(rules, "equipment")
  end

  test "type_config/2 returns nil for unknown type" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert InventoryRules.type_config(rules, "language") == nil
  end

  test "type_for_activate_command/2 finds type by activate_command" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert {"equipment", config} = InventoryRules.type_for_activate_command(rules, "equip")
    assert config.activate_command == "equip"
  end

  test "type_for_activate_command/2 finds type by deactivate_command" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert {"equipment", _config} = InventoryRules.type_for_activate_command(rules, "unequip")
  end

  test "type_for_activate_command/2 returns nil for unknown verb" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert InventoryRules.type_for_activate_command(rules, "prepare") == nil
  end

  defp spell_type_with_progressions do
    %{
      "inventory_type" => %{
        "spell" => %{
          "activate_command" => "prepare",
          "activation_field" => "prepared",
          "schema" => %{"prepared" => %{"type" => "boolean", "default" => false}},
          "add_on_progression" => [
            %{"progression" => "cantrips", "auto_activate" => true},
            %{"progression" => "spells_known"}
          ]
        }
      }
    }
  end

  test "from_map/1 parses auto_activate progression config" do
    assert {:ok, rules} = InventoryRules.from_map(spell_type_with_progressions())
    [cantrip_prog, _] = rules.types["spell"].add_on_progression

    assert %InventoryRules.ProgressionConfig{progression: "cantrips", auto_activate: true} =
             cantrip_prog
  end

  test "from_map/1 parses default progression config" do
    assert {:ok, rules} = InventoryRules.from_map(spell_type_with_progressions())
    [_, spells_prog] = rules.types["spell"].add_on_progression

    assert %InventoryRules.ProgressionConfig{progression: "spells_known", auto_activate: false} =
             spells_prog
  end

  test "type_for_progression/2 returns type and config for a matching progression" do
    map = %{
      "inventory_type" => %{
        "spell" => %{
          "schema" => %{"prepared" => %{"type" => "boolean", "default" => false}},
          "add_on_progression" => [%{"progression" => "spells_known"}]
        }
      }
    }

    assert {:ok, rules} = InventoryRules.from_map(map)
    assert {"spell", prog_config} = InventoryRules.type_for_progression(rules, "spells_known")
    assert prog_config.progression == "spells_known"
  end

  test "type_for_progression/2 returns nil for unknown progression" do
    assert {:ok, rules} = InventoryRules.from_map(minimal_map())
    assert InventoryRules.type_for_progression(rules, "spells_known") == nil
  end

  test "preparation_types/1 returns types with preparation config" do
    map = %{
      "inventory_type" => %{
        "equipment" => %{
          "schema" => %{"equipped" => %{"type" => "boolean", "default" => false}}
        },
        "spell" => %{
          "schema" => %{"prepared" => %{"type" => "boolean", "default" => false}},
          "preparation" => %{
            "mode_field" => "preparation_mode",
            "activation_mode" => "prepared",
            "pool_field" => "preparation_pool",
            "cap_field" => "preparation_cap",
            "level_field" => "level",
            "max_level_node" => ["character_trait", "max_spell_level", "level"]
          }
        }
      }
    }

    assert {:ok, rules} = InventoryRules.from_map(map)
    prep_types = InventoryRules.preparation_types(rules)
    assert length(prep_types) == 1
    assert {"spell", _} = hd(prep_types)
  end

  defp preparation_map do
    %{
      "inventory_type" => %{
        "spell" => %{
          "schema" => %{"prepared" => %{"type" => "boolean", "default" => false}},
          "preparation" => %{
            "mode_field" => "preparation_mode",
            "activation_mode" => "prepared",
            "pool_field" => "preparation_pool",
            "cap_field" => "preparation_cap",
            "level_field" => "level",
            "max_level_node" => ["character_trait", "max_spell_level", "level"],
            "always_prepared" => %{"metadata_key" => "always_prepared"},
            "auto_activate_when" => %{"class_field" => "preparation_mode", "class_value" => "all"},
            "pool" => %{
              "class_spells" => %{
                "class_filter_field" => "classes",
                "management" => "add_remove"
              },
              "spellbook" => %{
                "scope_type" => "character_progression",
                "scope_id" => "spells_known",
                "management" => "toggle_field"
              }
            }
          }
        }
      }
    }
  end

  test "from_map/1 parses preparation core fields" do
    assert {:ok, rules} = InventoryRules.from_map(preparation_map())
    prep = rules.types["spell"].preparation

    assert %InventoryRules.PreparationConfig{
             mode_field: "preparation_mode",
             activation_mode: "prepared",
             cap_field: "preparation_cap",
             max_level_node: {"character_trait", "max_spell_level", "level"}
           } = prep
  end

  test "from_map/1 parses preparation always_prepared and auto_activate_when" do
    assert {:ok, rules} = InventoryRules.from_map(preparation_map())
    prep = rules.types["spell"].preparation

    assert prep.always_prepared_metadata_key == "always_prepared"
    assert prep.auto_activate_when_field == "preparation_mode"
    assert prep.auto_activate_when_value == "all"
  end

  test "from_map/1 parses preparation pool configs" do
    assert {:ok, rules} = InventoryRules.from_map(preparation_map())
    prep = rules.types["spell"].preparation

    assert %InventoryRules.PoolConfig{class_filter_field: "classes", management: :add_remove} =
             prep.pools["class_spells"]

    assert %InventoryRules.PoolConfig{
             scope_type: "character_progression",
             scope_id: "spells_known",
             management: :toggle_field
           } = prep.pools["spellbook"]
  end

  test "from_map/1 returns error for unknown pool management strategy" do
    map = %{
      "inventory_type" => %{
        "spell" => %{
          "schema" => %{"prepared" => %{"type" => "boolean", "default" => false}},
          "preparation" => %{
            "mode_field" => "preparation_mode",
            "activation_mode" => "prepared",
            "pool_field" => "preparation_pool",
            "cap_field" => "preparation_cap",
            "level_field" => "level",
            "max_level_node" => ["character_trait", "max_spell_level", "level"],
            "pool" => %{
              "bad_pool" => %{"management" => "some_unknown_strategy"}
            }
          }
        }
      }
    }

    assert {:error, {:unknown_pool_management, "some_unknown_strategy"}} =
             InventoryRules.from_map(map)
  end
end
