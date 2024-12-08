defmodule ExTTRPGDevTest.Characters.Character do
  use ExUnit.Case
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystems

  doctest ExTTRPGDev.Characters.Character,
    except: [
      to_json!: 1,
      gen_character!: 1
    ]

  test "gen_character!/1" do
    dnd_5e_srd = RuleSystems.load_system!("dnd_5e_srd")
    generated_character = Character.gen_character!(dnd_5e_srd)

    assert generated_character.name != nil
    assert generated_character.metadata.slug != nil
    assert not String.contains?(generated_character.metadata.slug, " ")
    assert generated_character.metadata.rule_system == dnd_5e_srd.metadata

    # Assert that each ability spec is found within the generated character's ability_scores
    dnd_5e_srd.abilities.specs
    |> Enum.each(fn spec ->
      score = Map.get(generated_character.ability_scores, spec.name)
      assert score != nil, "Could not find ability #{spec.name} on generated character"
    end)
  end
end
