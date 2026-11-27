defmodule ExTTRPGDevTest.Characters.Rolls do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystem.{Dice, Graph, Node}
  alias ExTTRPGDev.RuleSystems

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

  describe "concept_roll!/4 with dice-valued nodes" do
    # The SRD system plus a "feature" type whose damage nodes are dice: one
    # computed with dice() from the character's level, one from a mapping,
    # rolled by a roll definition that takes its dice from `dice_field`.
    setup do
      base = RuleSystems.load_system!("dnd_5e_srd")

      nodes =
        Map.merge(base.nodes, %{
          {"feature", "sneak_attack", "damage"} => %Node{
            type: :formula,
            formula: "dice(ceil(character_trait('character_level').level / 2), 6)"
          },
          {"feature", "martial_arts", "damage"} => %Node{
            type: :mapping,
            input: "character_trait('character_level').level",
            steps: [[1, Dice.parse!("1d4")], [5, Dice.parse!("1d6")]]
          },
          {"feature", "martial_arts", "bonus"} => %Node{
            type: :formula,
            formula: "ability('dexterity').modifier"
          }
        })

      concept_metadata =
        Map.merge(base.concept_metadata, %{
          {"feature", "sneak_attack"} => %{"name" => "Sneak Attack"},
          {"feature", "martial_arts"} => %{"name" => "Martial Arts"},
          {"roll", "feature_damage"} => %{
            "target_type" => "feature",
            "dice_field" => "damage"
          }
        })

      {:ok, built} =
        Graph.build(%{
          nodes: nodes,
          effects: base.effects,
          rolling_methods: base.rolling_methods,
          concept_metadata: concept_metadata
        })

      system = %{base | graph: built.graph, nodes: nodes, concept_metadata: concept_metadata}

      generated =
        ~w[strength dexterity constitution wisdom intelligence charisma]
        |> Map.new(&{{"ability", &1, "base_score"}, 14})

      character = %Character{
        name: "Test Character",
        generated_values: generated,
        effects: [],
        decisions: [],
        metadata: %ExTTRPGDev.Characters.Metadata{
          slug: "test_dice_roll_char",
          rule_system: "dnd_5e_srd"
        }
      }

      {:ok, system: system, character: character}
    end

    defp put_roll(system, roll_meta) do
      put_in(system.concept_metadata[{"roll", "feature_damage"}], roll_meta)
    end

    test "rolls a dice() formula node", %{system: system, character: character} do
      result = Characters.concept_roll!(system, character, "feature", "sneak_attack")

      assert result.dice == "1d6"
      assert [die] = result.rolls
      assert die in 1..6
      assert result.bonus == 0
      assert result.total == die
    end

    test "rolls a dice-valued mapping node with an optional bonus", %{
      system: system,
      character: character
    } do
      system =
        put_roll(system, %{
          "target_type" => "feature",
          "dice_field" => "damage",
          "bonus_field" => "bonus"
        })

      result = Characters.concept_roll!(system, character, "feature", "martial_arts")

      assert result.dice == "1d4"
      assert result.bonus == 2
      assert result.total == Enum.sum(result.rolls) + 2
    end

    test "a non-integer bonus is added as before", %{system: system, character: character} do
      nodes =
        Map.put(system.nodes, {"feature", "martial_arts", "bonus"}, %Node{
          type: :formula,
          formula: "5 / 2"
        })

      system =
        %{system | nodes: nodes}
        |> put_roll(%{
          "target_type" => "feature",
          "dice" => "1d1",
          "bonus_field" => "bonus"
        })

      result = Characters.concept_roll!(system, character, "feature", "martial_arts")

      assert result.bonus == 2.5
      assert result.total == 3.5
    end

    test "rolls a mixed pool and groups its rolls by term", %{
      system: system,
      character: character
    } do
      system = put_roll(system, %{"target_type" => "feature", "dice" => "2d1+1d4+3"})

      result = Characters.concept_roll!(system, character, "feature", "sneak_attack")

      assert result.dice == "2d1+1d4+3"
      assert [%{dice: "2d1", rolls: [1, 1]}, %{dice: "1d4", rolls: [d4]}] = result.rolls_by_term
      assert result.rolls == [1, 1, d4]
      assert result.total == 5 + d4
    end

    test "static dice accept full notation", %{system: system, character: character} do
      system = put_roll(system, %{"target_type" => "feature", "dice" => "2d1+3"})

      result = Characters.concept_roll!(system, character, "feature", "sneak_attack")

      assert result.dice == "2d1+3"
      assert result.rolls == [1, 1]
      assert result.total == 5
    end

    test "raises on a misconfigured roll definition", %{system: system, character: character} do
      cases = [
        {%{"target_type" => "feature"}, ~r/neither "dice" nor "dice_field"/},
        {%{"target_type" => "feature", "dice" => "1d6", "dice_field" => "damage"},
         ~r/both "dice" and "dice_field"/},
        {%{"target_type" => "feature", "dice" => "lots"}, ~r/invalid dice notation/},
        {%{"target_type" => "feature", "dice_field" => "missing"}, ~r/does not have/},
        {%{"target_type" => "feature", "dice_field" => "damage", "bonus_field" => "damage"},
         ~r/rather than a number/}
      ]

      for {roll_meta, message} <- cases do
        assert_raise RuntimeError, message, fn ->
          Characters.concept_roll!(
            put_roll(system, roll_meta),
            character,
            "feature",
            "martial_arts"
          )
        end
      end
    end

    test "raises when a dice_field node isn't dice", %{system: system, character: character} do
      system =
        put_roll(system, %{"target_type" => "feature", "dice_field" => "bonus"})

      assert_raise RuntimeError, ~r/resolved to 2 rather than dice/, fn ->
        Characters.concept_roll!(system, character, "feature", "martial_arts")
      end
    end
  end
end
