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
    assert character.metadata.rule_system_version == system.module.version
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

  defp equipped_field_rules do
    {:ok, rules} =
      ExTTRPGDev.RuleSystem.InventoryRules.from_map(%{
        "inventory_type" => %{
          "equipment" => %{
            "activation_field" => "equipped",
            "schema" => %{"equipped" => %{"type" => "boolean", "default" => false}}
          }
        }
      })

    rules
  end

  defp fighter_system(inventory_rules, starting_equipment) do
    RuleSystems.load_system!("dnd_5e_srd")
    |> Map.put(:inventory_rules, inventory_rules)
    |> Map.put(:concept_metadata, %{
      {"class", "fighter"} => %{"starting_equipment" => starting_equipment}
    })
  end

  defp fighter_decisions, do: [%Decision{scope: nil, choice: "class", selection: "fighter"}]

  test "gen_character!/2 populates inventory from starting_equipment on chosen concepts" do
    starting_equipment = [
      %{"type" => "equipment", "id" => "chain_mail"},
      %{"type" => "equipment", "id" => "longsword", "fields" => %{"equipped" => true}}
    ]

    system = fighter_system(equipped_field_rules(), starting_equipment)
    character = Character.gen_character!(system, fighter_decisions())

    assert length(character.inventory) == 2
    chain_mail = Enum.find(character.inventory, &(&1.concept_id == "chain_mail"))
    longsword = Enum.find(character.inventory, &(&1.concept_id == "longsword"))

    assert chain_mail.concept_type == "equipment"
    assert chain_mail.fields["equipped"] == false
    assert longsword.fields["equipped"] == true
  end

  test "gen_character!/2 ignores starting_equipment for non-inventoriable types" do
    {:ok, empty_rules} = ExTTRPGDev.RuleSystem.InventoryRules.from_map(%{})
    starting_equipment = [%{"type" => "equipment", "id" => "longsword"}]
    system = fighter_system(empty_rules, starting_equipment)
    character = Character.gen_character!(system, fighter_decisions())
    assert character.inventory == []
  end

  test "gen_character!/2 raises clearly for a starting-equipment entry missing type/id" do
    {:ok, inventory_rules} = ExTTRPGDev.RuleSystem.InventoryRules.from_map(%{})
    system = fighter_system(inventory_rules, [%{"id" => "longsword"}])

    assert_raise RuntimeError, ~r/invalid starting-equipment spec/, fn ->
      Character.gen_character!(system, fighter_decisions())
    end
  end

  test "gen_character!/2 raises clearly for a starting-equipment entry with an invalid field" do
    starting_equipment = [
      %{"type" => "equipment", "id" => "longsword", "fields" => %{"typo_field" => true}}
    ]

    system = fighter_system(equipped_field_rules(), starting_equipment)

    assert_raise RuntimeError, ~r/invalid starting-equipment spec/, fn ->
      Character.gen_character!(system, fighter_decisions())
    end
  end

  test "inventory_from_decisions/2 reports a structured error for a spec missing type/id, without raising" do
    {:ok, inventory_rules} = ExTTRPGDev.RuleSystem.InventoryRules.from_map(%{})
    system = fighter_system(inventory_rules, [%{"id" => "longsword"}])

    assert {:ok, %{items: [], errors: [error]}} =
             Character.inventory_from_decisions(fighter_decisions(), system)

    assert error.spec == %{"id" => "longsword"}
    assert error.reason == :missing_type_or_id
  end

  test "inventory_from_decisions/2 skips, without an error, a type the system doesn't configure as inventoriable" do
    {:ok, empty_rules} = ExTTRPGDev.RuleSystem.InventoryRules.from_map(%{})
    starting_equipment = [%{"type" => "equipment", "id" => "longsword"}]
    system = fighter_system(empty_rules, starting_equipment)

    assert {:ok, %{items: [], errors: []}} =
             Character.inventory_from_decisions(fighter_decisions(), system)
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

  test "from_json/1 round-trips a character and returns {:ok, character}" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    original = Character.gen_character!(system)

    json = original |> Character.to_json_map() |> Jason.encode!()
    assert {:ok, restored} = Character.from_json(json)

    assert restored.name == original.name
    assert restored.metadata.slug == original.metadata.slug
  end

  test "from_json/1 round-trips level_classes" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    original = %{Character.gen_character!(system) | level_classes: ["fighter", "wizard"]}

    json = original |> Character.to_json_map() |> Jason.encode!()

    assert {:ok, %Character{level_classes: ["fighter", "wizard"]}} = Character.from_json(json)
  end

  test "from_json/1 defaults level_classes to [] for characters saved without it" do
    system = RuleSystems.load_system!("dnd_5e_srd")

    json =
      system
      |> Character.gen_character!()
      |> Character.to_json_map()
      |> Map.delete("level_classes")
      |> Jason.encode!()

    assert {:ok, %Character{level_classes: []}} = Character.from_json(json)
  end

  test "from_json/1 returns {:error, {:invalid_character_data, _}} for malformed JSON" do
    assert {:error, {:invalid_character_data, _message}} = Character.from_json("not valid json")
  end

  test "from_json/1 returns {:error, {:invalid_character_data, _}} for valid JSON with the wrong shape" do
    assert {:error, {:invalid_character_data, _message}} =
             Character.from_json(Jason.encode!(%{"generated_values" => %{"missing_colons" => 1}}))
  end

  test "from_json!/1 raises for malformed JSON" do
    assert_raise RuntimeError, ~r/Failed to parse character JSON/, fn ->
      Character.from_json!("not valid json")
    end
  end

  test "to_json_map/1 and from_json!/1 round-trip correctly" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    original = Character.gen_character!(system)

    json = original |> Character.to_json_map() |> Jason.encode!()
    restored = Character.from_json!(json)

    assert restored.name == original.name
    assert restored.metadata.slug == original.metadata.slug
    assert restored.metadata.rule_system == original.metadata.rule_system
    assert restored.metadata.rule_system_version == original.metadata.rule_system_version
    assert restored.generated_values == original.generated_values
    assert restored.effects == original.effects
    assert restored.decisions == original.decisions
    assert restored.inventory == original.inventory
  end

  test "from_json!/1 leaves rule_system_version nil for characters saved without it" do
    system = RuleSystems.load_system!("dnd_5e_srd")

    json =
      system
      |> Character.gen_character!()
      |> Character.to_json_map()
      |> update_in(["metadata"], &Map.delete(&1, "rule_system_version"))
      |> Jason.encode!()

    assert %Character{metadata: %{rule_system_version: nil}} = Character.from_json!(json)
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

    json = original |> Character.to_json_map() |> Jason.encode!()
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
    json = original |> Character.to_json_map() |> Jason.encode!()
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

    json = original |> Character.to_json_map() |> Jason.encode!()
    restored = Character.from_json!(json)

    assert length(restored.effects) == 2

    assert %Effect{target: {"ability", "strength", "total_score"}, value: 2} in restored.effects

    assert %Effect{target: {"ability", "dexterity", "total_score"}, value: -1} in restored.effects
  end

  describe "slugify/1" do
    test "always produces a valid slug, or an empty string" do
      names = [
        "Mr. Whiskers",
        "Zoë",
        "Éowyn",
        "日本の剣士",
        "a/b",
        "..\\evil",
        "Sir \"Bob\" [II]",
        "tab\tname",
        "zoe\u0308",
        "!!!",
        String.duplicate("ë", 500)
      ]

      for name <- names do
        slug = Character.slugify(name)

        assert slug == "" or ExTTRPGDev.Slug.valid?(slug),
               "#{inspect(name)} slugified to invalid #{inspect(slug)}"
      end
    end

    test "decomposed and composed spellings slugify identically" do
      assert Character.slugify("Zoe\u0308") == Character.slugify("Zoë")
    end

    test "long names are truncated without splitting a letter" do
      slug = Character.slugify(String.duplicate("ë", 500))
      assert String.valid?(slug)
      assert byte_size(slug) <= ExTTRPGDev.Slug.max_bytes()
    end

    test "whitespace of any kind becomes an underscore" do
      assert Character.slugify("tab\tname") == "tab_name"
    end
  end
end
