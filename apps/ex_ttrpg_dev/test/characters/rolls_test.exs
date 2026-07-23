defmodule ExTTRPGDevTest.Characters.Rolls do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
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
end
