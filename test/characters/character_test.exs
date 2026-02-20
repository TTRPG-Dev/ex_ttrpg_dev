defmodule ExTTRPGDevTest.Characters.Character do
  use ExUnit.Case
  alias ExTTRPGDev.Characters.Character
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
    assert character.active_contributions == []
  end

  test "gen_character!/1 generates all six attribute base scores" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    character = Character.gen_character!(system)

    attrs = ~w(strength dexterity constitution wisdom intelligence charisma)

    for attr <- attrs do
      key = {"attr", attr, "base_score"}
      score = Map.get(character.generated_values, key)
      assert is_integer(score), "Missing or non-integer base_score for #{attr}"
      assert score >= 3 and score <= 18, "Score #{score} for #{attr} out of expected range"
    end
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
    assert restored.active_contributions == original.active_contributions
  end
end
