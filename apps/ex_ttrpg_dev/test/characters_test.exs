defmodule ExTTRPGDevTest.Characters do
  use ExUnit.Case
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
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
