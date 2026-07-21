defmodule ExTTRPGDevTest.Characters.Character do
  use ExUnit.Case
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.Characters.{Character, Decision, InventoryItem}
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

  test "gen_character!/1 rolls methodless generated nodes via the default rolling method" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    key = {"ability", "strength", "base_score"}
    nodes = Map.update!(system.nodes, key, &%{&1 | method: nil})

    character = Character.gen_character!(%{system | nodes: nodes})

    score = character.generated_values[key]
    assert is_integer(score) and score >= 3 and score <= 18
  end

  test "gen_character!/1 raises clearly for an unknown rolling method" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    key = {"ability", "strength", "base_score"}
    nodes = Map.update!(system.nodes, key, &%{&1 | method: "bogus"})

    assert_raise RuntimeError, ~r/unknown rolling method "bogus"/, fn ->
      Character.gen_character!(%{system | nodes: nodes})
    end
  end

  test "gen_character!/1 raises clearly when no method is set and no default exists" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    key = {"ability", "strength", "base_score"}
    nodes = Map.update!(system.nodes, key, &%{&1 | method: nil})

    no_defaults =
      Map.new(system.rolling_methods, fn {id, method} -> {id, %{method | default: false}} end)

    assert_raise RuntimeError, ~r/no rolling method declares\s+default = true/, fn ->
      Character.gen_character!(%{system | nodes: nodes, rolling_methods: no_defaults})
    end
  end

  test "gen_character!/2 stores provided decisions" do
    system = RuleSystems.load_system!("dnd_5e_srd")

    decisions = [
      %Decision{scope: nil, choice: "race", selection: "hill_dwarf"},
      %Decision{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"}
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
        "inventory_type" => %{
          "equipment" => %{
            "activation_field" => "equipped",
            "schema" => %{"equipped" => %{"type" => "boolean", "default" => false}}
          }
        }
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

    decisions = [%Decision{scope: nil, choice: "class", selection: "fighter"}]
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

    decisions = [%Decision{scope: nil, choice: "class", selection: "fighter"}]
    character = Character.gen_character!(system, decisions)
    assert character.inventory == []
  end

  test "gen_character!/2 adds inventory item for equipment choice decision" do
    {:ok, inventory_rules} =
      ExTTRPGDev.RuleSystem.InventoryRules.from_map(%{
        "inventory_type" => %{
          "equipment" => %{
            "activation_field" => "equipped",
            "schema" => %{"equipped" => %{"type" => "boolean", "default" => false}}
          }
        }
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
      %Decision{scope: {"class", "fighter"}, choice: "starting_weapon", selection: "longsword"}
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
      %Decision{scope: nil, choice: "race", selection: "dwarf"},
      %Decision{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"}
    ]

    original = Character.gen_character!(system, decisions)
    json = original |> Character.to_json_map() |> Poison.encode!()
    restored = Character.from_json!(json)

    assert restored.decisions == decisions
  end

  test "to_json_map/1 keeps the stable saved-character JSON shape" do
    system = RuleSystems.load_system!("dnd_5e_srd")

    decisions = [
      %Decision{scope: nil, choice: "race", selection: "dwarf"},
      %Decision{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"}
    ]

    original = Character.gen_character!(system, decisions)

    original = %{
      original
      | effects: [%Effect{target: {"ability", "strength", "total_score"}, value: 2}]
    }

    json_map = Character.to_json_map(original)

    assert %{"scope" => nil, "choice" => "race", "selection" => "dwarf"} in json_map["decisions"]

    assert %{"scope" => "race:dwarf", "choice" => "subrace", "selection" => "hill_dwarf"} in json_map[
             "decisions"
           ]

    assert json_map["effects"] == [%{"target" => "ability:strength:total_score", "value" => 2}]
  end

  test "to_json_map/1 and from_json!/1 round-trip preserves effects" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    original = Character.gen_character!(system)

    original = %{
      original
      | effects: [
          %Effect{target: {"ability", "strength", "total_score"}, value: 2},
          %Effect{target: {"ability", "dexterity", "total_score"}, value: -1}
        ]
    }

    json = original |> Character.to_json_map() |> Poison.encode!()
    restored = Character.from_json!(json)

    assert length(restored.effects) == 2

    assert %Effect{target: {"ability", "strength", "total_score"}, value: 2} in restored.effects

    assert %Effect{target: {"ability", "dexterity", "total_score"}, value: -1} in restored.effects
  end
end
