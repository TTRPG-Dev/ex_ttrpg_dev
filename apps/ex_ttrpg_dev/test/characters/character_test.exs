defmodule ExTTRPGDevTest.Characters.Character do
  use ExUnit.Case
  alias ExTTRPGDev.Characters.{Character, InventoryItem}
  alias ExTTRPGDev.RuleSystems

  doctest ExTTRPGDev.Characters.Character,
    except: [
      gen_character!: 1,
      from_json!: 1,
      to_json_map: 1
    ]

  test "gen_character!/1 produces a valid character" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    character = Character.gen_character!(system)

    assert character.name != nil
    assert character.metadata.slug != nil
    refute String.contains?(character.metadata.slug, " ")
    assert character.metadata.rule_system == "dnd_5e_srd"
    assert character.effects == []
    assert character.decisions == []
    assert character.inventory == []
  end

  test "gen_character!/2 stores provided decisions" do
    system = RuleSystems.load_system!("dnd_5e_srd")

    decisions = [
      %{scope: nil, choice: "race", selection: "hill_dwarf"},
      %{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"}
    ]

    character = Character.gen_character!(system, decisions)
    assert character.decisions == decisions
  end

  test "gen_character!/1 generates all six attribute base scores" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    character = Character.gen_character!(system)

    attrs = ~w(strength dexterity constitution wisdom intelligence charisma)

    for attr <- attrs do
      key = {"ability", attr, "base_score"}
      score = Map.get(character.generated_values, key)
      assert is_integer(score), "Missing or non-integer base_score for #{attr}"
      assert score >= 3 and score <= 18, "Score #{score} for #{attr} out of expected range"
    end
  end

  test "gen_character!/2 populates inventory from starting_equipment on chosen concepts" do
    {:ok, inventory_rules} =
      ExTTRPGDev.RuleSystem.InventoryRules.from_map(%{
        "inventory" => %{"inventoriable_types" => ["equipment"]},
        "inventory_item_schema" => %{"equipped" => %{"type" => "boolean", "default" => false}}
      })

    system =
      RuleSystems.load_system!("dnd_5e_srd")
      |> Map.put(:inventory_rules, inventory_rules)
      |> Map.put(:concept_metadata, %{
        {"class", "fighter"} => %{
          "name" => "Fighter",
          "starting_equipment" => [
            %{"type" => "equipment", "id" => "chain_mail"},
            %{"type" => "equipment", "id" => "longsword", "fields" => %{"equipped" => true}}
          ]
        }
      })

    decisions = [%{scope: nil, choice: "class", selection: "fighter"}]
    character = Character.gen_character!(system, decisions)

    assert length(character.inventory) == 2
    chain_mail = Enum.find(character.inventory, &(&1.concept_id == "chain_mail"))
    longsword = Enum.find(character.inventory, &(&1.concept_id == "longsword"))

    assert chain_mail.concept_type == "equipment"
    assert chain_mail.fields["equipped"] == false
    assert longsword.fields["equipped"] == true
  end

  test "gen_character!/2 ignores starting_equipment for non-inventoriable types" do
    {:ok, empty_rules} = ExTTRPGDev.RuleSystem.InventoryRules.from_map(%{})

    system =
      RuleSystems.load_system!("dnd_5e_srd")
      |> Map.put(:inventory_rules, empty_rules)
      |> Map.put(:concept_metadata, %{
        {"class", "fighter"} => %{
          "starting_equipment" => [%{"type" => "equipment", "id" => "longsword"}]
        }
      })

    decisions = [%{scope: nil, choice: "class", selection: "fighter"}]
    character = Character.gen_character!(system, decisions)
    assert character.inventory == []
  end

  test "gen_character!/2 adds inventory item for equipment choice decision" do
    {:ok, inventory_rules} =
      ExTTRPGDev.RuleSystem.InventoryRules.from_map(%{
        "inventory" => %{"inventoriable_types" => ["equipment"]},
        "inventory_item_schema" => %{"equipped" => %{"type" => "boolean", "default" => false}}
      })

    system =
      RuleSystems.load_system!("dnd_5e_srd")
      |> Map.put(:inventory_rules, inventory_rules)
      |> Map.put(:concept_metadata, %{
        {"class", "fighter"} => %{
          "choices" => %{
            "starting_weapon" => %{
              "type" => "equipment",
              "grants_to" => "inventory",
              "options" => ["longsword", "shortsword"]
            }
          }
        }
      })

    decisions = [
      %{scope: {"class", "fighter"}, choice: "starting_weapon", selection: "longsword"}
    ]

    character = Character.gen_character!(system, decisions)

    assert length(character.inventory) == 1
    [item] = character.inventory
    assert item.concept_type == "equipment"
    assert item.concept_id == "longsword"
  end

  test "to_json_map/1 and from_json!/1 round-trip correctly" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    original = Character.gen_character!(system)

    json = original |> Character.to_json_map() |> Poison.encode!()
    restored = Character.from_json!(json)

    assert restored.name == original.name
    assert restored.metadata.slug == original.metadata.slug
    assert restored.metadata.rule_system == original.metadata.rule_system
    assert restored.generated_values == original.generated_values
    assert restored.effects == original.effects
    assert restored.decisions == original.decisions
    assert restored.inventory == original.inventory
  end

  test "to_json_map/1 and from_json!/1 round-trip preserves inventory" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    original = Character.gen_character!(system)

    original = %{
      original
      | inventory: [
          %InventoryItem{
            concept_type: "equipment",
            concept_id: "longsword",
            fields: %{"equipped" => true, "condition" => 0.8}
          }
        ]
    }

    json = original |> Character.to_json_map() |> Poison.encode!()
    restored = Character.from_json!(json)

    assert length(restored.inventory) == 1
    [item] = restored.inventory
    assert item.concept_type == "equipment"
    assert item.concept_id == "longsword"
    assert item.fields["equipped"] == true
    assert item.fields["condition"] == 0.8
  end

  test "to_json_map/1 and from_json!/1 round-trip preserves decisions" do
    system = RuleSystems.load_system!("dnd_5e_srd")

    decisions = [
      %{scope: nil, choice: "race", selection: "dwarf"},
      %{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"}
    ]

    original = Character.gen_character!(system, decisions)
    json = original |> Character.to_json_map() |> Poison.encode!()
    restored = Character.from_json!(json)

    assert restored.decisions == decisions
  end

  test "to_json_map/1 and from_json!/1 round-trip preserves effects" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    original = Character.gen_character!(system)

    original = %{
      original
      | effects: [
          %{target: {"ability", "strength", "total_score"}, value: 2},
          %{target: {"ability", "dexterity", "total_score"}, value: -1}
        ]
    }

    json = original |> Character.to_json_map() |> Poison.encode!()
    restored = Character.from_json!(json)

    assert length(restored.effects) == 2

    assert %{target: {"ability", "strength", "total_score"}, value: 2} in restored.effects

    assert %{target: {"ability", "dexterity", "total_score"}, value: -1} in restored.effects
  end
end
