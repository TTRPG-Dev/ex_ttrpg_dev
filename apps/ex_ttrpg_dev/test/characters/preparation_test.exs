defmodule ExTTRPGDevTest.Characters.Preparation do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, Decision, InventoryItem}
  alias ExTTRPGDev.RuleSystem.InventoryRules
  alias ExTTRPGDev.RuleSystem.Node
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  defp minimal_character(decisions) do
    %Character{
      name: "Test",
      generated_values: %{},
      effects: [],
      decisions: decisions,
      metadata: %ExTTRPGDev.Characters.Metadata{slug: "test", rule_system: "dnd_5e_srd"}
    }
  end

  defp spell_inv_rules do
    {:ok, rules} =
      InventoryRules.from_map(%{
        "inventory_type" => %{
          "equipment" => %{
            "activation_field" => "equipped",
            "schema" => %{"equipped" => %{"type" => "boolean", "default" => false}}
          },
          "spell" => %{
            "activation_field" => "prepared",
            "activate_command" => "prepare",
            "schema" => %{"prepared" => %{"type" => "boolean", "default" => false}},
            "add_on_progression" => [
              %{"progression" => "cantrips", "auto_activate" => true},
              %{"progression" => "spells_known"}
            ],
            "preparation" => %{
              "mode_field" => "preparation_mode",
              "activation_mode" => "prepared",
              "pool_field" => "preparation_pool",
              "cap_field" => "preparation_cap",
              "level_field" => "level",
              "max_level_node" => ["character_trait", "max_spell_level", "level"],
              "always_prepared" => %{"metadata_key" => "always_prepared"},
              "auto_activate_when" => %{
                "class_field" => "preparation_mode",
                "class_value" => "all"
              },
              "pool" => %{
                "spellbook" => %{
                  "scope_type" => "character_progression",
                  "scope_id" => "spells_known",
                  "management" => "toggle_field"
                },
                "class_spells" => %{
                  "class_filter_field" => "classes",
                  "management" => "add_remove"
                }
              }
            }
          }
        }
      })

    rules
  end

  defp spell_system(concept_metadata \\ %{}) do
    %LoadedSystem{
      module: %{character_building_choices: [%{concept_type: "class"}]},
      graph: nil,
      nodes: %{},
      rolling_methods: %{},
      effects: [],
      concept_metadata: concept_metadata,
      inventory_rules: spell_inv_rules()
    }
  end

  defp built_spell_system(nodes, concept_metadata, building_choices \\ [%{concept_type: "class"}]) do
    {:ok, built} =
      ExTTRPGDev.RuleSystem.Graph.build(%{
        nodes: nodes,
        effects: [],
        concept_metadata: concept_metadata,
        rolling_methods: %{}
      })

    %LoadedSystem{
      module: %{character_building_choices: building_choices},
      graph: built.graph,
      nodes: built.nodes,
      rolling_methods: %{},
      effects: [],
      concept_metadata: concept_metadata,
      inventory_rules: spell_inv_rules()
    }
  end

  describe "activate/4" do
    test "returns error for unknown inventory type" do
      assert {:error, {:unknown_inventory_type, "weapon"}} =
               Characters.activate(spell_system(), minimal_character([]), "weapon", [])
    end

    test "returns error for non-preparation type" do
      assert {:error, {:not_a_preparation_type, "equipment"}} =
               Characters.activate(spell_system(), minimal_character([]), "equipment", [])
    end

    test "returns error when no class decision has preparation mode" do
      assert {:error, :no_preparation_class} =
               Characters.activate(spell_system(), minimal_character([]), "spell", [])
    end

    test "returns error when class preparation mode is not prepared" do
      meta = %{{"class", "bard"} => %{"preparation_mode" => "all"}}
      character = minimal_character([%Decision{scope: nil, choice: "class", selection: "bard"}])

      assert {:error, {:mode_not_prepared, "all"}} =
               Characters.activate(spell_system(meta), character, "spell", [])
    end

    test "toggle_field: sets prepared true for listed items and false for others" do
      nodes = %{
        {"class", "wizard", "preparation_cap"} => %Node{type: :accumulator, base: "3"},
        {"character_trait", "max_spell_level", "level"} => %Node{type: :accumulator, base: "2"}
      }

      concept_metadata = %{
        {"class", "wizard"} => %{
          "preparation_mode" => "prepared",
          "preparation_pool" => "spellbook"
        },
        {"spell", "fire_bolt"} => %{"level" => 1},
        {"spell", "cure_wounds"} => %{"level" => 1}
      }

      system = built_spell_system(nodes, concept_metadata)

      decisions = [
        %Decision{scope: nil, choice: "class", selection: "wizard"},
        %Decision{
          scope: {"character_progression", "spells_known"},
          choice: "choice_1",
          selection: "fire_bolt"
        },
        %Decision{
          scope: {"character_progression", "spells_known"},
          choice: "choice_2",
          selection: "cure_wounds"
        }
      ]

      inventory = [
        %InventoryItem{
          concept_type: "spell",
          concept_id: "fire_bolt",
          fields: %{"prepared" => false}
        },
        %InventoryItem{
          concept_type: "spell",
          concept_id: "cure_wounds",
          fields: %{"prepared" => false}
        }
      ]

      character = %{minimal_character(decisions) | inventory: inventory}

      assert {:ok, updated} = Characters.activate(system, character, "spell", ["fire_bolt"])

      assert Enum.find(updated.inventory, &(&1.concept_id == "fire_bolt")).fields["prepared"] ==
               true

      assert Enum.find(updated.inventory, &(&1.concept_id == "cure_wounds")).fields["prepared"] ==
               false
    end

    test "toggle_field: preserves cantrips (outside eligible pool) when preparing leveled spells" do
      nodes = %{
        {"class", "wizard", "preparation_cap"} => %Node{type: :accumulator, base: "3"},
        {"character_trait", "max_spell_level", "level"} => %Node{type: :accumulator, base: "2"}
      }

      concept_metadata = %{
        {"class", "wizard"} => %{
          "preparation_mode" => "prepared",
          "preparation_pool" => "spellbook"
        },
        {"spell", "prestidigitation"} => %{"level" => 0},
        {"spell", "magic_missile"} => %{"level" => 1}
      }

      system = built_spell_system(nodes, concept_metadata)

      decisions = [
        %Decision{scope: nil, choice: "class", selection: "wizard"},
        %Decision{
          scope: {"character_progression", "spells_known"},
          choice: "choice_1",
          selection: "magic_missile"
        }
      ]

      inventory = [
        %InventoryItem{
          concept_type: "spell",
          concept_id: "prestidigitation",
          fields: %{"prepared" => true}
        },
        %InventoryItem{
          concept_type: "spell",
          concept_id: "magic_missile",
          fields: %{"prepared" => false}
        }
      ]

      character = %{minimal_character(decisions) | inventory: inventory}

      assert {:ok, updated} = Characters.activate(system, character, "spell", ["magic_missile"])

      assert Enum.find(updated.inventory, &(&1.concept_id == "magic_missile")).fields["prepared"] ==
               true

      assert Enum.find(updated.inventory, &(&1.concept_id == "prestidigitation")).fields[
               "prepared"
             ] == true
    end

    test "add_remove: preserves cantrips when preparing leveled spells" do
      nodes = %{
        {"class", "cleric", "preparation_cap"} => %Node{type: :accumulator, base: "4"},
        {"character_trait", "max_spell_level", "level"} => %Node{type: :accumulator, base: "2"}
      }

      concept_metadata = %{
        {"class", "cleric"} => %{
          "preparation_mode" => "prepared",
          "preparation_pool" => "class_spells"
        },
        {"spell", "sacred_flame"} => %{"level" => 0, "classes" => ["cleric"]},
        {"spell", "bless"} => %{"level" => 1, "classes" => ["cleric"]},
        {"spell", "cure_wounds"} => %{"level" => 1, "classes" => ["cleric"]}
      }

      system = built_spell_system(nodes, concept_metadata)

      decisions = [%Decision{scope: nil, choice: "class", selection: "cleric"}]

      inventory = [
        %InventoryItem{
          concept_type: "spell",
          concept_id: "sacred_flame",
          fields: %{"prepared" => true}
        }
      ]

      character = %{minimal_character(decisions) | inventory: inventory}

      assert {:ok, updated} = Characters.activate(system, character, "spell", ["bless"])

      spell_inventory = Enum.filter(updated.inventory, &(&1.concept_type == "spell"))

      # sacred_flame (cantrip) preserved; bless added; cure_wounds (eligible, not requested) absent
      assert MapSet.new(spell_inventory, & &1.concept_id) == MapSet.new(["sacred_flame", "bless"])
      assert Enum.all?(spell_inventory, &(&1.fields["prepared"] == true))
    end
  end

  describe "add_to_typed_inventory/4" do
    test "returns character unchanged when progression has no inventory type" do
      {:ok, inv_rules} = InventoryRules.from_map(%{})

      system = %LoadedSystem{
        module: nil,
        graph: nil,
        nodes: %{},
        rolling_methods: %{},
        effects: [],
        concept_metadata: %{},
        inventory_rules: inv_rules
      }

      character = minimal_character([])

      assert {:ok, ^character} =
               Characters.add_to_typed_inventory(system, character, "spells_known", "fire_bolt")
    end

    test "determines initial activation from progression config and class condition" do
      meta = %{{"class", "bard"} => %{"preparation_mode" => "all"}}
      bard_char = minimal_character([%Decision{scope: nil, choice: "class", selection: "bard"}])

      {:ok, cantrip_char} =
        Characters.add_to_typed_inventory(
          spell_system(),
          minimal_character([]),
          "cantrips",
          "fire_bolt"
        )

      {:ok, spell_char} =
        Characters.add_to_typed_inventory(
          spell_system(),
          minimal_character([]),
          "spells_known",
          "cure_wounds"
        )

      {:ok, bard_spell_char} =
        Characters.add_to_typed_inventory(
          spell_system(meta),
          bard_char,
          "spells_known",
          "vicious_mockery"
        )

      assert hd(cantrip_char.inventory).fields["prepared"] == true
      assert hd(spell_char.inventory).fields["prepared"] == false
      assert hd(bard_spell_char.inventory).fields["prepared"] == true
    end
  end

  describe "preparation_state/3" do
    test "returns error for unknown inventory type" do
      assert {:error, {:unknown_inventory_type, "weapon"}} =
               Characters.preparation_state(spell_system(), minimal_character([]), "weapon")
    end

    test "returns mode nil when character has no class with preparation config" do
      assert {:ok, %{mode: nil}} =
               Characters.preparation_state(spell_system(), minimal_character([]), "spell")
    end

    test "returns full preparation state for a character with a prepared-mode class" do
      nodes = %{
        {"class", "wizard", "preparation_cap"} => %Node{type: :accumulator, base: "3"},
        {"character_trait", "max_spell_level", "level"} => %Node{type: :accumulator, base: "2"}
      }

      concept_metadata = %{
        {"class", "wizard"} => %{
          "preparation_mode" => "prepared",
          "preparation_pool" => "spellbook"
        },
        {"spell", "fire_bolt"} => %{"level" => 1}
      }

      system = built_spell_system(nodes, concept_metadata)

      decisions = [
        %Decision{scope: nil, choice: "class", selection: "wizard"},
        %Decision{
          scope: {"character_progression", "spells_known"},
          choice: "c1",
          selection: "fire_bolt"
        }
      ]

      inventory = [
        %InventoryItem{
          concept_type: "spell",
          concept_id: "fire_bolt",
          fields: %{"prepared" => true}
        }
      ]

      character = %{minimal_character(decisions) | inventory: inventory}

      assert {:ok, %{mode: "prepared", cap: 3, prepared: ["fire_bolt"]}} =
               Characters.preparation_state(system, character, "spell")
    end

    test "always_prepared spells from subclass appear and are filtered by max spell level" do
      nodes = %{
        {"class", "cleric", "preparation_cap"} => %Node{type: :accumulator, base: "4"},
        {"character_trait", "max_spell_level", "level"} => %Node{type: :accumulator, base: "1"}
      }

      concept_metadata = %{
        {"class", "cleric"} => %{
          "preparation_mode" => "prepared",
          "preparation_pool" => "class_spells",
          "choices" => %{"subclass" => %{"type" => "class"}}
        },
        {"class", "life_domain"} => %{
          "always_prepared" => ["bless", "cure_wounds", "hold_person"]
        },
        {"spell", "bless"} => %{"level" => 1, "classes" => ["cleric"]},
        {"spell", "cure_wounds"} => %{"level" => 1, "classes" => ["cleric"]},
        {"spell", "hold_person"} => %{"level" => 2, "classes" => ["cleric"]}
      }

      system = built_spell_system(nodes, concept_metadata)

      decisions = [
        %Decision{scope: nil, choice: "class", selection: "cleric"},
        %Decision{scope: {"class", "cleric"}, choice: "subclass", selection: "life_domain"}
      ]

      character = minimal_character(decisions)

      assert {:ok, state} = Characters.preparation_state(system, character, "spell")
      assert state.mode == "prepared"
      # bless and cure_wounds are within max_spell_level 1; hold_person (level 2) is filtered out
      assert Enum.sort(state.always_prepared) == ["bless", "cure_wounds"]
    end

    test "always_prepared accumulates from all active concepts, not just subclass" do
      nodes = %{
        {"class", "cleric", "preparation_cap"} => %Node{type: :accumulator, base: "4"},
        {"character_trait", "max_spell_level", "level"} => %Node{type: :accumulator, base: "2"}
      }

      concept_metadata = %{
        {"class", "cleric"} => %{
          "preparation_mode" => "prepared",
          "preparation_pool" => "class_spells",
          "choices" => %{"subclass" => %{"type" => "class"}}
        },
        # subclass contributes one spell
        {"class", "life_domain"} => %{"always_prepared" => ["bless"]},
        # race contributes a different spell via the same metadata key
        {"race", "aasimar"} => %{"always_prepared" => ["guiding_bolt"]},
        {"spell", "bless"} => %{"level" => 1, "classes" => ["cleric"]},
        {"spell", "guiding_bolt"} => %{"level" => 1, "classes" => ["cleric"]}
      }

      system =
        built_spell_system(nodes, concept_metadata, [
          %{concept_type: "class"},
          %{concept_type: "race"}
        ])

      decisions = [
        %Decision{scope: nil, choice: "class", selection: "cleric"},
        %Decision{scope: {"class", "cleric"}, choice: "subclass", selection: "life_domain"},
        %Decision{scope: nil, choice: "race", selection: "aasimar"}
      ]

      character = minimal_character(decisions)

      assert {:ok, state} = Characters.preparation_state(system, character, "spell")
      assert Enum.sort(state.always_prepared) == ["bless", "guiding_bolt"]
    end
  end
end
