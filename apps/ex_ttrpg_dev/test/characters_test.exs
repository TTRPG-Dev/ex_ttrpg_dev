defmodule ExTTRPGDevTest.Characters do
  use ExUnit.Case
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, InventoryItem}
  alias ExTTRPGDev.RuleSystems

  doctest ExTTRPGDev.Characters,
    except: [
      character_file_path!: 1,
      character_exists?: 1,
      save_character!: 1,
      save_character!: 2,
      list_characters!: 0,
      load_character!: 1,
      concept_roll!: 4
    ]

  def build_test_character do
    RuleSystems.list_systems()
    |> List.first()
    |> RuleSystems.load_system!()
    |> Character.gen_character!()
  end

  def save_test_character do
    character = build_test_character()
    Characters.save_character!(character)
    character
  end

  def delete_test_character(%Character{} = character) do
    File.rm(Characters.character_file_path!(character))
  end

  test "character_exists?/1" do
    character = build_test_character()
    assert not Characters.character_exists?(character)
    assert not Characters.character_exists?(character.metadata.slug)

    Characters.save_character!(character)
    assert Characters.character_exists?(character)
    assert Characters.character_exists?(character.metadata.slug)

    # cleanup
    delete_test_character(character)
  end

  test "save_character!/1" do
    character = build_test_character()
    assert not Characters.character_exists?(character)

    Characters.save_character!(character)
    assert Characters.character_exists?(character)

    assert_raise RuntimeError, fn -> Characters.save_character!(character) end

    # cleanup
    delete_test_character(character)
  end

  test "save_character!/2" do
    character = build_test_character()
    assert not Characters.character_exists?(character)

    Characters.save_character!(character)
    assert Characters.character_exists?(character)

    Characters.save_character!(character, true)
    assert Characters.character_exists?(character)

    # cleanup
    delete_test_character(character)
  end

  test "list_characters!/0" do
    characters_list_first = Characters.list_characters!()
    character = save_test_character()
    characters_list_second = Characters.list_characters!()
    assert Enum.count(characters_list_first) < Enum.count(characters_list_second)
    assert Enum.member?(characters_list_second, character.metadata.slug)

    # cleanup
    delete_test_character(character)
  end

  test "load_character/1" do
    character = save_test_character()
    loaded_character = Characters.load_character!(character.metadata.slug)
    assert character == loaded_character

    delete_test_character(character)
  end

  test "delete_character/1 deletes an existing character and returns :ok" do
    character = save_test_character()
    assert Characters.character_exists?(character)

    assert :ok = Characters.delete_character(character.metadata.slug)
    refute Characters.character_exists?(character)
  end

  test "delete_character/1 returns error for unknown slug" do
    assert {:error, :not_found} = Characters.delete_character("nonexistent_character_xyz")
  end

  describe "active_concepts/2" do
    test "returns empty set for no decisions" do
      assert MapSet.new() == Characters.active_concepts([], %{})
    end

    test "returns root concept for a single root decision" do
      decisions = [%{scope: nil, choice: "race", selection: "human"}]
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
        %{scope: nil, choice: "race", selection: "dwarf"},
        %{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"}
      ]

      result = Characters.active_concepts(decisions, @dwarf_metadata)
      assert MapSet.member?(result, {"race", "dwarf"})
      assert MapSet.member?(result, {"race", "hill_dwarf"})
    end

    test "does not activate sub-concept when no decision is made for a choice" do
      decisions = [%{scope: nil, choice: "race", selection: "dwarf"}]
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
        %{scope: nil, choice: "class", selection: "fighter"},
        %{scope: {"class", "fighter"}, choice: "starting_armor", selection: "chain_mail"}
      ]

      result = Characters.active_concepts(decisions, @fighter_with_inventory_choice)
      assert MapSet.member?(result, {"class", "fighter"})
      refute MapSet.member?(result, {"equipment", "chain_mail"})
    end
  end

  describe "random_decisions/1" do
    setup do
      {:ok, system: RuleSystems.load_system!("dnd_5e_srd")}
    end

    test "returns one root decision per character choice", %{system: system} do
      decisions = Characters.random_decisions(system)
      root = Enum.filter(decisions, &(&1.scope == nil))
      assert length(root) == length(system.module.character_building_choices)
    end

    test "root decision choice matches the character_choice concept_type", %{system: system} do
      decisions = Characters.random_decisions(system)

      for %{concept_type: type_id} <- system.module.character_building_choices do
        assert Enum.any?(decisions, &(&1.scope == nil and &1.choice == type_id))
      end
    end

    test "selected root race is not a subrace", %{system: system} do
      decisions = Characters.random_decisions(system)
      root_race = Enum.find(decisions, &(&1.scope == nil and &1.choice == "race"))

      subraces = ~w[hill_dwarf high_elf lightfoot_halfling rock_gnome]

      refute root_race.selection in subraces
    end

    test "equipment choices (grants_to: inventory) produce a decision but do not recurse", %{
      system: system
    } do
      concept_metadata =
        Map.put(system.concept_metadata, {"class", "fighter"}, %{
          "choices" => %{
            "starting_weapon" => %{
              "type" => "equipment",
              "grants_to" => "inventory",
              "options" => ["longsword", "shortsword"]
            }
          }
        })

      system = %{system | concept_metadata: concept_metadata}

      for _ <- 1..10 do
        decisions = Characters.random_decisions(system)

        weapon_decision =
          Enum.find(decisions, fn d ->
            d.scope != nil and elem(d.scope, 0) == "class" and d.choice == "starting_weapon"
          end)

        if weapon_decision do
          assert weapon_decision.selection in ["longsword", "shortsword"]
          # The selected equipment id should not appear as a scope in any decision
          refute Enum.any?(decisions, fn d ->
                   d.scope != nil and elem(d.scope, 1) == weapon_decision.selection
                 end)
        end
      end
    end

    test "races with subraces produce a subrace decision", %{system: system} do
      races_with_subraces = ~w[dwarf elf halfling gnome]

      for _ <- 1..20 do
        decisions = Characters.random_decisions(system)
        root_race = Enum.find(decisions, &(&1.scope == nil and &1.choice == "race"))

        if root_race.selection in races_with_subraces do
          parent_scope = {"race", root_race.selection}
          assert Enum.any?(decisions, &(&1.scope == parent_scope and &1.choice == "subrace"))
        end
      end
    end
  end

  describe "active_effects/2" do
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

    test "includes system effects for active concepts" do
      system =
        minimal_system(
          [
            %{
              source: {"class", "fighter"},
              target: {"saving_throw", "strength", "modifier"},
              value: 2
            }
          ],
          %{{"class", "fighter"} => %{}}
        )

      character = minimal_character([%{scope: nil, choice: "class", selection: "fighter"}])
      effects = Characters.active_effects(system, character)
      assert Enum.any?(effects, &(&1.source == {"class", "fighter"}))
    end

    test "excludes system effects for inactive concepts" do
      system =
        minimal_system(
          [
            %{
              source: {"class", "fighter"},
              target: {"saving_throw", "strength", "modifier"},
              value: 2
            }
          ],
          %{}
        )

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
          %{scope: {"class", "fighter"}, choice: "skill_proficiency_1", selection: "athletics"}
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
            %{
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
          [%{source: {"equipment", "shortsword"}, target: {"stat", "atk", "bonus"}, value: 1}],
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
          %{scope: {"race", "elf"}, choice: "subrace", selection: "high_elf"}
        ])

      assert Characters.active_effects(system, character) == []
    end
  end

  describe "pending_choices/3" do
    @level_binding %{{"character_trait", "character_level", "level"} => 3}

    @hp_progression %{
      "name" => "Hit Points",
      "required_count" => "character_trait('character_level').level - 1",
      "effect_target" => "character_trait('max_hit_points').points"
    }

    defp progression_system(progressions) do
      minimal_system(
        [],
        Map.new(progressions, fn {id, meta} ->
          {{"character_progression", id}, meta}
        end)
      )
    end

    test "returns empty list when no character_progression concepts exist" do
      system = minimal_system([], %{})
      assert Characters.pending_choices(system, minimal_character([]), %{}) == []
    end

    test "returns a pending entry when required slots exceed decisions made" do
      system = progression_system(%{"hp_per_level" => @hp_progression})
      # level 3 → required 2, decisions made 0 → 2 pending
      [entry] = Characters.pending_choices(system, minimal_character([]), @level_binding)
      assert entry.type == :pending
      assert entry.id == "hp_per_level"
      assert entry.name == "Hit Points"
      assert entry.count == 2
      assert entry.effect_target == "character_trait('max_hit_points').points"
    end

    test "reduces pending count by decisions already made for that progression" do
      system = progression_system(%{"hp_per_level" => @hp_progression})

      decisions = [
        %{
          scope: {"character_progression", "hp_per_level"},
          choice: "choice_1",
          selection: "rolled"
        }
      ]

      # level 3 → required 2, made 1 → 1 pending
      [entry] = Characters.pending_choices(system, minimal_character(decisions), @level_binding)
      assert entry.count == 1
    end

    test "returns empty when all required slots are filled" do
      system = progression_system(%{"hp_per_level" => @hp_progression})

      decisions = [
        %{
          scope: {"character_progression", "hp_per_level"},
          choice: "choice_1",
          selection: "rolled"
        },
        %{
          scope: {"character_progression", "hp_per_level"},
          choice: "choice_2",
          selection: "average"
        }
      ]

      # level 3 → required 2, made 2 → empty
      assert Characters.pending_choices(system, minimal_character(decisions), @level_binding) ==
               []
    end

    test "does not count decisions scoped to a different progression" do
      system =
        progression_system(%{"hp_per_level" => @hp_progression, "other" => @hp_progression})

      decisions = [
        %{scope: {"character_progression", "other"}, choice: "choice_1", selection: "rolled"}
      ]

      result = Characters.pending_choices(system, minimal_character(decisions), @level_binding)
      hp_entry = Enum.find(result, &(&1.id == "hp_per_level"))
      assert hp_entry.count == 2
    end

    test "returns empty for required_count when formula binding is missing" do
      system = progression_system(%{"hp_per_level" => @hp_progression})
      assert Characters.pending_choices(system, minimal_character([]), %{}) == []
    end

    test "returns an available entry when available_when is truthy" do
      progression = %{
        "name" => "Spend XP",
        "available_when" => "character_trait('experience_points').total",
        "effect_target" => "skill('athletics').modifier"
      }

      system = progression_system(%{"spend_xp" => progression})
      resolved = %{{"character_trait", "experience_points", "total"} => 100}
      [entry] = Characters.pending_choices(system, minimal_character([]), resolved)
      assert entry.type == :available
      assert entry.id == "spend_xp"
      assert entry.effect_target == "skill('athletics').modifier"
    end

    test "returns empty when available_when evaluates to 0" do
      progression = %{
        "name" => "Spend XP",
        "available_when" => "character_trait('experience_points').total",
        "effect_target" => "skill('athletics').modifier"
      }

      system = progression_system(%{"spend_xp" => progression})
      resolved = %{{"character_trait", "experience_points", "total"} => 0}
      assert Characters.pending_choices(system, minimal_character([]), resolved) == []
    end

    test "returns empty when available_when evaluates to false" do
      progression = %{
        "name" => "Spend XP",
        "available_when" => "character_trait('experience_points').total > 0",
        "effect_target" => "skill('athletics').modifier"
      }

      system = progression_system(%{"spend_xp" => progression})
      resolved = %{{"character_trait", "experience_points", "total"} => 0}
      assert Characters.pending_choices(system, minimal_character([]), resolved) == []
    end

    test "returns empty for available_when when formula binding is missing" do
      progression = %{
        "available_when" => "character_trait('experience_points').total",
        "effect_target" => "skill('athletics').modifier"
      }

      system = progression_system(%{"spend_xp" => progression})
      assert Characters.pending_choices(system, minimal_character([]), %{}) == []
    end

    test "returns empty when progression has neither required_count nor available_when" do
      progression = %{
        "name" => "Inert",
        "effect_target" => "character_trait('max_hit_points').points"
      }

      system = progression_system(%{"inert" => progression})
      assert Characters.pending_choices(system, minimal_character([]), %{}) == []
    end

    test "falls back to id as name when name is not present" do
      progression = Map.delete(@hp_progression, "name")
      system = progression_system(%{"hp_per_level" => progression})
      [entry] = Characters.pending_choices(system, minimal_character([]), @level_binding)
      assert entry.name == "hp_per_level"
    end

    test "resolves roll_reference from the character's active root decision" do
      concept_metadata = %{
        {"character_progression", "hp_per_level"} =>
          Map.put(@hp_progression, "roll_reference", "class.hit_die"),
        {"class", "fighter"} => %{"hit_die" => "d10"}
      }

      system = minimal_system([], concept_metadata)
      decisions = [%{scope: nil, choice: "class", selection: "fighter"}]
      [entry] = Characters.pending_choices(system, minimal_character(decisions), @level_binding)
      assert entry.roll == "d10"
    end

    test "roll is nil when roll_reference has no matching decision on the character" do
      concept_metadata = %{
        {"character_progression", "hp_per_level"} =>
          Map.put(@hp_progression, "roll_reference", "class.hit_die")
      }

      system = minimal_system([], concept_metadata)
      [entry] = Characters.pending_choices(system, minimal_character([]), @level_binding)
      assert entry.roll == nil
    end

    test "roll is nil when no roll_reference is declared" do
      system = progression_system(%{"hp_per_level" => @hp_progression})
      [entry] = Characters.pending_choices(system, minimal_character([]), @level_binding)
      assert entry.roll == nil
    end

    test "returns entries for multiple progressions" do
      other = %{
        "name" => "Other",
        "required_count" => "character_trait('character_level').level - 1",
        "effect_target" => "skill('athletics').modifier"
      }

      system = progression_system(%{"hp_per_level" => @hp_progression, "other" => other})
      result = Characters.pending_choices(system, minimal_character([]), @level_binding)
      assert Enum.map(result, & &1.id) |> Enum.sort() == ["hp_per_level", "other"]
    end

    @cantrip_progression %{
      "name" => "Cantrip",
      "required_count" => "2",
      "type" => "spell",
      "filter" => %{"level" => 0}
    }

    @spell_meta %{
      {"spell", "fire_bolt"} => %{"level" => 0, "classes" => ["wizard"]},
      {"spell", "mage_hand"} => %{"level" => 0, "classes" => ["wizard"]},
      {"spell", "cure_wounds"} => %{"level" => 1, "classes" => ["cleric"]},
      {"spell", "sacred_flame"} => %{"level" => 0, "classes" => ["cleric"]}
    }

    defp spell_system(progressions, spell_meta) do
      minimal_system(
        [],
        Map.merge(
          Map.new(progressions, fn {id, meta} -> {{"character_progression", id}, meta} end),
          spell_meta
        )
      )
    end

    test "spell progression includes options filtered by level and active class" do
      system = spell_system(%{"cantrips" => @cantrip_progression}, @spell_meta)

      decisions = [%{scope: nil, choice: "class", selection: "wizard"}]
      [entry] = Characters.pending_choices(system, minimal_character(decisions), %{})

      assert entry.id == "cantrips"
      assert entry.count == 2
      assert entry.effect_target == nil
      assert entry.roll == nil
      assert Enum.sort(entry.options) == ["fire_bolt", "mage_hand"]
    end

    test "spell progression returns no options when no class active" do
      system = spell_system(%{"cantrips" => @cantrip_progression}, @spell_meta)

      [entry] = Characters.pending_choices(system, minimal_character([]), %{})

      assert entry.options == []
    end

    test "spell progression with min/max level filter" do
      progression = %{
        "name" => "Spell",
        "required_count" => "2",
        "type" => "spell",
        "filter" => %{
          "min_level" => 1,
          "max_level_node" => "character_trait('max_spell_level').level"
        }
      }

      system = spell_system(%{"spells_known" => progression}, @spell_meta)
      resolved = %{{"character_trait", "max_spell_level", "level"} => 1}
      decisions = [%{scope: nil, choice: "class", selection: "cleric"}]

      [entry] = Characters.pending_choices(system, minimal_character(decisions), resolved)

      assert entry.id == "spells_known"
      assert entry.options == ["cure_wounds"]
    end
  end

  describe "concept_roll!/4" do
    setup do
      system = RuleSystems.load_system!("dnd_5e_srd")
      attrs = ~w[strength dexterity constitution wisdom intelligence charisma]
      generated = Map.new(attrs, &{{"ability", &1, "base_score"}, 10})

      character = %Character{
        name: "Test Character",
        generated_values: generated,
        effects: [],
        decisions: [],
        metadata: %ExTTRPGDev.Characters.Metadata{
          slug: "test_roll_char",
          rule_system: "dnd_5e_srd"
        }
      }

      {:ok, system: system, character: character}
    end

    test "returns a valid result for a known concept", %{system: system, character: character} do
      result = Characters.concept_roll!(system, character, "skill", "acrobatics")

      assert Enum.sum(result.rolls) in 1..20
      assert result.bonus == 0
      assert result.total == Enum.sum(result.rolls) + result.bonus
      assert result.type_id == "skill"
      assert result.concept_id == "acrobatics"
      assert result.dice == "1d20"
    end

    test "raises when no roll is defined for the concept type", %{
      system: system,
      character: character
    } do
      assert_raise RuntimeError, ~r/No roll defined/, fn ->
        Characters.concept_roll!(system, character, "ability", "strength")
      end
    end

    test "raises for an unknown concept", %{system: system, character: character} do
      assert_raise RuntimeError, ~r/not found/, fn ->
        Characters.concept_roll!(system, character, "skill", "not_a_real_skill")
      end
    end
  end
end
