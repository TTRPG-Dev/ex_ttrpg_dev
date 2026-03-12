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

    test "recurses into sub-choices when a decision exists for them" do
      concept_metadata = %{
        {"race", "dwarf"} => %{
          "choices" => %{"subrace" => %{"type" => "race", "options" => ["hill_dwarf"]}}
        }
      }

      decisions = [
        %{scope: nil, choice: "race", selection: "dwarf"},
        %{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"}
      ]

      result = Characters.active_concepts(decisions, concept_metadata)
      assert MapSet.member?(result, {"race", "dwarf"})
      assert MapSet.member?(result, {"race", "hill_dwarf"})
    end

    test "does not activate sub-concept when no decision is made for a choice" do
      concept_metadata = %{
        {"race", "dwarf"} => %{
          "choices" => %{"subrace" => %{"type" => "race", "options" => ["hill_dwarf"]}}
        }
      }

      decisions = [%{scope: nil, choice: "race", selection: "dwarf"}]
      result = Characters.active_concepts(decisions, concept_metadata)
      assert MapSet.member?(result, {"race", "dwarf"})
      refute MapSet.member?(result, {"race", "hill_dwarf"})
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
