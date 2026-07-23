defmodule ExTTRPGDevTest.Characters.Effects do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, Decision, InventoryItem}
  alias ExTTRPGDev.RuleSystem.Effect

  defp minimal_system(effects, concept_metadata) do
    %ExTTRPGDev.RuleSystems.LoadedSystem{
      module: nil,
      graph: nil,
      nodes: %{},
      rolling_methods: %{},
      effects: effects,
      concept_metadata: concept_metadata
    }
  end

  defp minimal_character(decisions) do
    %Character{
      name: "Test",
      generated_values: %{},
      effects: [],
      decisions: decisions,
      metadata: %ExTTRPGDev.Characters.Metadata{slug: "test", rule_system: "dnd_5e_srd"}
    }
  end

  describe "active_concepts/2" do
    test "returns empty set for no decisions" do
      assert MapSet.new() == Characters.active_concepts([], %{})
    end

    test "returns root concept for a single root decision" do
      decisions = [%Decision{scope: nil, choice: "race", selection: "human"}]
      result = Characters.active_concepts(decisions, %{})
      assert MapSet.member?(result, {"race", "human"})
    end

    @dwarf_metadata %{
      {"race", "dwarf"} => %{
        "choices" => %{"subrace" => %{"type" => "race", "options" => ["hill_dwarf"]}}
      }
    }

    test "recurses into sub-choices when a decision exists for them" do
      decisions = [
        %Decision{scope: nil, choice: "race", selection: "dwarf"},
        %Decision{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"}
      ]

      result = Characters.active_concepts(decisions, @dwarf_metadata)
      assert MapSet.member?(result, {"race", "dwarf"})
      assert MapSet.member?(result, {"race", "hill_dwarf"})
    end

    test "does not activate sub-concept when no decision is made for a choice" do
      decisions = [%Decision{scope: nil, choice: "race", selection: "dwarf"}]
      result = Characters.active_concepts(decisions, @dwarf_metadata)
      assert MapSet.member?(result, {"race", "dwarf"})
      refute MapSet.member?(result, {"race", "hill_dwarf"})
    end

    @fighter_with_inventory_choice %{
      {"class", "fighter"} => %{
        "choices" => %{
          "starting_armor" => %{
            "type" => "equipment",
            "grants_to" => "inventory",
            "options" => ["chain_mail"]
          }
        }
      }
    }

    test "does not recurse into choices with grants_to: inventory" do
      decisions = [
        %Decision{scope: nil, choice: "class", selection: "fighter"},
        %Decision{scope: {"class", "fighter"}, choice: "starting_armor", selection: "chain_mail"}
      ]

      result = Characters.active_concepts(decisions, @fighter_with_inventory_choice)
      assert MapSet.member?(result, {"class", "fighter"})
      refute MapSet.member?(result, {"equipment", "chain_mail"})
    end
  end

  describe "active_effects/2" do
    @fighter_effect %Effect{
      source: {"class", "fighter"},
      target: {"saving_throw", "strength", "modifier"},
      value: 2
    }

    test "includes system effects for active concepts" do
      system = minimal_system([@fighter_effect], %{{"class", "fighter"} => %{}})

      character =
        minimal_character([%Decision{scope: nil, choice: "class", selection: "fighter"}])

      effects = Characters.active_effects(system, character)
      assert Enum.any?(effects, &(&1.source == {"class", "fighter"}))
    end

    test "excludes system effects for inactive concepts" do
      system = minimal_system([@fighter_effect], %{})
      character = minimal_character([])
      effects = Characters.active_effects(system, character)
      refute Enum.any?(effects, &(&1.source == {"class", "fighter"}))
    end

    test "generates effects from decisions with contributes_field" do
      concept_metadata = %{
        {"class", "fighter"} => %{
          "choices" => %{
            "skill_proficiency_1" => %{
              "type" => "skill",
              "contributes_field" => "modifier",
              "contributes_value" => "character_trait('proficiency_bonus').bonus",
              "options" => ["athletics", "acrobatics"]
            }
          }
        }
      }

      system = minimal_system([], concept_metadata)

      character =
        minimal_character([
          %Decision{
            scope: {"class", "fighter"},
            choice: "skill_proficiency_1",
            selection: "athletics"
          }
        ])

      effects = Characters.active_effects(system, character)

      assert Enum.any?(
               effects,
               &(&1.source == {"class", "fighter"} and
                   &1.target == {"skill", "athletics", "modifier"} and
                   &1.value == "character_trait('proficiency_bonus').bonus")
             )
    end

    test "includes effects from inventory items with item_fields populated" do
      system =
        minimal_system(
          [
            %Effect{
              source: {"equipment", "longsword"},
              target: {"character_trait", "ac", "value"},
              value: 2,
              when: "item.equipped"
            }
          ],
          %{}
        )

      item = %InventoryItem{
        concept_type: "equipment",
        concept_id: "longsword",
        fields: %{"equipped" => true}
      }

      character = %{minimal_character([]) | inventory: [item]}
      effects = Characters.active_effects(system, character)

      assert length(effects) == 1
      [effect] = effects
      assert effect.source == {"equipment", "longsword"}
      assert effect.item_fields == %{"equipped" => true}
    end

    test "produces one effect entry per inventory item even for the same concept" do
      system =
        minimal_system(
          [
            %Effect{
              source: {"equipment", "shortsword"},
              target: {"stat", "atk", "bonus"},
              value: 1
            }
          ],
          %{}
        )

      item1 = %InventoryItem{concept_type: "equipment", concept_id: "shortsword", fields: %{}}
      item2 = %InventoryItem{concept_type: "equipment", concept_id: "shortsword", fields: %{}}

      character = %{minimal_character([]) | inventory: [item1, item2]}
      effects = Characters.active_effects(system, character)
      assert length(effects) == 2
    end

    test "does not generate effects for choices without contributes_field" do
      concept_metadata = %{
        {"race", "elf"} => %{
          "choices" => %{
            "subrace" => %{"type" => "race", "options" => ["high_elf"]}
          }
        }
      }

      system = minimal_system([], concept_metadata)

      character =
        minimal_character([
          %Decision{scope: {"race", "elf"}, choice: "subrace", selection: "high_elf"}
        ])

      assert Characters.active_effects(system, character) == []
    end
  end
end
