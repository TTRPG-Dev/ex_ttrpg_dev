defmodule ExTTRPGDev.RuleSystem.EvaluatorTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.{Evaluator, Graph, Loader}

  doctest ExTTRPGDev.RuleSystem.Evaluator

  defp minimal_system do
    loader_data = %{
      nodes: %{
        {"attr", "strength", "base_score"} => %{type: :generated, method: "standard"},
        {"attr", "strength", "total_score"} => %{
          type: :accumulator,
          base: "attr('strength').base_score"
        },
        {"attr", "strength", "modifier"} => %{
          type: :formula,
          formula: "floor((attr('strength').total_score - 10) / 2)"
        }
      },
      rolling_methods: %{},
      concept_metadata: %{},
      effects: []
    }

    {:ok, system} = Graph.build(loader_data)
    system
  end

  defp dnd_path do
    Application.app_dir(:ex_ttrpg_dev, "priv/system_configs/dnd_5e_srd")
  end

  test "evaluate/3 computes modifier correctly for score 18" do
    system = minimal_system()
    generated = %{{"attr", "strength", "base_score"} => 18}

    assert {:ok, resolved} = Evaluator.evaluate(system, generated)
    assert resolved[{"attr", "strength", "modifier"}] == 4
  end

  test "evaluate/3 floors negative modifiers correctly for score 9" do
    system = minimal_system()
    generated = %{{"attr", "strength", "base_score"} => 9}

    assert {:ok, resolved} = Evaluator.evaluate(system, generated)
    assert resolved[{"attr", "strength", "modifier"}] == -1
  end

  test "evaluate/3 applies active effects to accumulator" do
    system = minimal_system()
    generated = %{{"attr", "strength", "base_score"} => 16}

    effects = [%{target: {"attr", "strength", "total_score"}, value: 2}]

    assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
    # total_score = 16 + 2 = 18, modifier = floor((18-10)/2) = 4
    assert resolved[{"attr", "strength", "total_score"}] == 18
    assert resolved[{"attr", "strength", "modifier"}] == 4
  end

  test "evaluate/3 resolves mapping node from input value" do
    loader_data = %{
      nodes: %{
        {"char", "xp", "total"} => %{type: :accumulator, base: "0"},
        {"char", "level", "value"} => %{
          type: :mapping,
          input: "char('xp').total",
          steps: [[0, 1], [300, 2], [900, 3]]
        }
      },
      rolling_methods: %{},
      concept_metadata: %{},
      effects: []
    }

    {:ok, system} = Graph.build(loader_data)

    assert {:ok, r0} = Evaluator.evaluate(system, %{})
    assert r0[{"char", "level", "value"}] == 1

    assert {:ok, r1} =
             Evaluator.evaluate(system, %{}, [%{target: {"char", "xp", "total"}, value: 300}])

    assert r1[{"char", "level", "value"}] == 2

    assert {:ok, r2} =
             Evaluator.evaluate(system, %{}, [%{target: {"char", "xp", "total"}, value: 850}])

    assert r2[{"char", "level", "value"}] == 2

    assert {:ok, r3} =
             Evaluator.evaluate(system, %{}, [%{target: {"char", "xp", "total"}, value: 900}])

    assert r3[{"char", "level", "value"}] == 3
  end

  test "evaluate/3 resolves formula-valued effects against current node values" do
    loader_data = %{
      nodes: %{
        {"trait", "prof", "bonus"} => %{type: :accumulator, base: "2"},
        {"attr", "strength", "base_score"} => %{type: :generated, method: "standard"},
        {"attr", "strength", "total_score"} => %{
          type: :accumulator,
          base: "attr('strength').base_score"
        },
        {"attr", "strength", "modifier"} => %{
          type: :formula,
          formula: "floor((attr('strength').total_score - 10) / 2)"
        },
        {"save", "strength", "modifier"} => %{
          type: :accumulator,
          base: "attr('strength').modifier"
        }
      },
      rolling_methods: %{},
      concept_metadata: %{},
      effects: [
        %{
          source: {"class", "fighter", nil},
          target: {"save", "strength", "modifier"},
          value: "trait('prof').bonus"
        }
      ]
    }

    {:ok, system} = Graph.build(loader_data)
    generated = %{{"attr", "strength", "base_score"} => 16}

    assert {:ok, resolved} = Evaluator.evaluate(system, generated, system.effects)
    # strength modifier = floor((16 - 10) / 2) = 3
    # proficiency bonus = 2
    # saving throw = 3 + 2 = 5
    assert resolved[{"save", "strength", "modifier"}] == 5
  end

  test "evaluate/3 returns error for missing generated value" do
    system = minimal_system()
    # Provide empty generated values — base_score will be missing
    assert {:error, {:missing_generated_value, _}} = Evaluator.evaluate(system, %{})
  end

  test "evaluate!/3 raises on error" do
    system = minimal_system()
    # Missing generated value triggers an error, which evaluate! should raise
    assert_raise RuntimeError, ~r/Evaluation failed/, fn ->
      Evaluator.evaluate!(system, %{})
    end
  end

  describe "when conditions" do
    test "skips effect when condition evaluates to false" do
      system = minimal_system()
      generated = %{{"attr", "strength", "base_score"} => 16}
      effects = [%{target: {"attr", "strength", "total_score"}, value: 2, when: "false"}]

      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"attr", "strength", "total_score"}] == 16
    end

    test "applies effect when condition evaluates to true" do
      system = minimal_system()
      generated = %{{"attr", "strength", "base_score"} => 16}
      effects = [%{target: {"attr", "strength", "total_score"}, value: 2, when: "true"}]

      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"attr", "strength", "total_score"}] == 18
    end

    test "applies effect when `when` key is absent (backward compat)" do
      system = minimal_system()
      generated = %{{"attr", "strength", "base_score"} => 16}
      effects = [%{target: {"attr", "strength", "total_score"}, value: 2}]

      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"attr", "strength", "total_score"}] == 18
    end

    test "evaluates `when` as a formula referencing resolved nodes" do
      loader_data = %{
        nodes: %{
          {"attr", "strength", "base_score"} => %{type: :generated, method: "standard"},
          {"attr", "strength", "total_score"} => %{
            type: :accumulator,
            base: "attr('strength').base_score"
          },
          {"flag", "active", "value"} => %{type: :accumulator, base: "0"}
        },
        rolling_methods: %{},
        concept_metadata: %{},
        effects: []
      }

      {:ok, system} = Graph.build(loader_data)
      generated = %{{"attr", "strength", "base_score"} => 16}

      # Effect applies only when flag is active (non-zero)
      effects = [
        %{target: {"flag", "active", "value"}, value: 1},
        %{target: {"attr", "strength", "total_score"}, value: 4, when: "flag('active').value"}
      ]

      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"attr", "strength", "total_score"}] == 20

      # Without the flag effect, the condition evaluates to 0 (false)
      effects_no_flag = [
        %{target: {"attr", "strength", "total_score"}, value: 4, when: "flag('active').value"}
      ]

      assert {:ok, resolved_no_flag} = Evaluator.evaluate(system, generated, effects_no_flag)
      assert resolved_no_flag[{"attr", "strength", "total_score"}] == 16
    end
  end

  describe "item_fields bindings" do
    test "applies effect when item.field resolves to true in when condition" do
      system = minimal_system()
      generated = %{{"attr", "strength", "base_score"} => 16}

      effects = [
        %{
          target: {"attr", "strength", "total_score"},
          value: 4,
          when: "item.equipped",
          item_fields: %{"equipped" => true}
        }
      ]

      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"attr", "strength", "total_score"}] == 20
    end

    test "skips effect when item.field resolves to false in when condition" do
      system = minimal_system()
      generated = %{{"attr", "strength", "base_score"} => 16}

      effects = [
        %{
          target: {"attr", "strength", "total_score"},
          value: 4,
          when: "item.equipped",
          item_fields: %{"equipped" => false}
        }
      ]

      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"attr", "strength", "total_score"}] == 16
    end

    test "substitutes item.field in value formula" do
      system = minimal_system()
      generated = %{{"attr", "strength", "base_score"} => 16}

      # condition is 0.5, so value formula "item.condition * 4" = 2.0
      effects = [
        %{
          target: {"attr", "strength", "total_score"},
          value: "item.condition * 4",
          item_fields: %{"condition" => 0.5}
        }
      ]

      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"attr", "strength", "total_score"}] == 18.0
    end
  end

  describe "integration" do
    setup do
      {:ok, loader_data} = Loader.load(dnd_path())
      {:ok, system} = Graph.build(loader_data)

      generated = %{
        {"ability", "strength", "base_score"} => 16,
        {"ability", "dexterity", "base_score"} => 14,
        {"ability", "constitution", "base_score"} => 14,
        {"ability", "wisdom", "base_score"} => 12,
        {"ability", "intelligence", "base_score"} => 10,
        {"ability", "charisma", "base_score"} => 8
      }

      {:ok, resolved} = Evaluator.evaluate(system, generated)
      %{system: system, generated: generated, resolved: resolved}
    end

    test "physical ability modifiers are calculated correctly", %{resolved: resolved} do
      assert resolved[{"ability", "strength", "modifier"}] == 3
      assert resolved[{"ability", "dexterity", "modifier"}] == 2
      assert resolved[{"ability", "constitution", "modifier"}] == 2
    end

    test "mental ability modifiers are calculated correctly", %{resolved: resolved} do
      assert resolved[{"ability", "wisdom", "modifier"}] == 1
      assert resolved[{"ability", "intelligence", "modifier"}] == 0
      assert resolved[{"ability", "charisma", "modifier"}] == -1
    end

    test "skills default to their governing ability modifier", %{resolved: resolved} do
      assert resolved[{"skill", "athletics", "modifier"}] == 3
      assert resolved[{"skill", "acrobatics", "modifier"}] == 2
      assert resolved[{"skill", "arcana", "modifier"}] == 0
    end

    test "proficiency bonus base value is 2 at level 1", %{resolved: resolved} do
      assert resolved[{"character_trait", "proficiency_bonus", "bonus"}] == 2
    end

    test "physical saving throws inherit ability modifier", %{resolved: resolved} do
      assert resolved[{"saving_throw", "strength", "modifier"}] == 3
      assert resolved[{"saving_throw", "dexterity", "modifier"}] == 2
      assert resolved[{"saving_throw", "constitution", "modifier"}] == 2
    end

    test "mental saving throws inherit ability modifier", %{resolved: resolved} do
      assert resolved[{"saving_throw", "wisdom", "modifier"}] == 1
      assert resolved[{"saving_throw", "intelligence", "modifier"}] == 0
      assert resolved[{"saving_throw", "charisma", "modifier"}] == -1
    end

    test "saving throw modifier increases when proficiency is applied as an effect",
         %{system: system, generated: generated} do
      effects = [%{target: {"saving_throw", "strength", "modifier"}, value: 2}]
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"saving_throw", "strength", "modifier"}] == 5
      assert resolved[{"saving_throw", "dexterity", "modifier"}] == 2
    end
  end

  describe "armor class integration" do
    setup do
      {:ok, loader_data} = Loader.load(dnd_path())
      {:ok, system} = Graph.build(loader_data)

      # All scores 10 (mod 0) except DEX 14 (mod +2)
      generated = %{
        {"ability", "strength", "base_score"} => 10,
        {"ability", "dexterity", "base_score"} => 14,
        {"ability", "constitution", "base_score"} => 10,
        {"ability", "wisdom", "base_score"} => 10,
        {"ability", "intelligence", "base_score"} => 10,
        {"ability", "charisma", "base_score"} => 10
      }

      %{system: system, generated: generated}
    end

    defp item_effects(system, concept_id, equipped) do
      system.effects
      |> Enum.filter(fn
        %{source: {"equipment", id}} -> id == concept_id
        _ -> false
      end)
      |> Enum.map(&Map.put(&1, :item_fields, %{"equipped" => equipped}))
    end

    test "unarmored default: 10 + DEX modifier", %{system: system, generated: generated} do
      assert {:ok, resolved} = Evaluator.evaluate(system, generated)
      assert resolved[{"character_trait", "armor_class", "total"}] == 12
    end

    test "light armor: ac_base + full DEX modifier", %{system: system, generated: generated} do
      # leather: ac_base 11; 11 + 2 = 13
      effects = item_effects(system, "leather_armor", true)
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "armor_class", "total"}] == 13
    end

    test "medium armor: DEX modifier applied within cap", %{system: system, generated: generated} do
      # chain_shirt: ac_base 13, DEX mod +2 (≤ cap of 2); 13 + 2 = 15
      effects = item_effects(system, "chain_shirt", true)
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "armor_class", "total"}] == 15
    end

    test "medium armor: DEX modifier capped at +2 when mod exceeds cap",
         %{system: system, generated: generated} do
      # breastplate: ac_base 14, DEX mod +4 (capped to +2); 14 + 2 = 16
      generated_high_dex = Map.put(generated, {"ability", "dexterity", "base_score"}, 18)
      effects = item_effects(system, "breastplate", true)
      assert {:ok, resolved} = Evaluator.evaluate(system, generated_high_dex, effects)
      assert resolved[{"character_trait", "armor_class", "total"}] == 16
    end

    test "heavy armor: ac_base only, DEX modifier ignored", %{
      system: system,
      generated: generated
    } do
      # chain_mail: ac_base 16; 16 + 0 = 16 regardless of DEX
      effects = item_effects(system, "chain_mail", true)
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "armor_class", "total"}] == 16
    end

    test "shield adds +2 to unarmored AC", %{system: system, generated: generated} do
      # unarmored + shield: 10 + 2 (shield) + 2 (DEX) = 14
      effects = item_effects(system, "shield", true)
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "armor_class", "total"}] == 14
    end

    test "light armor + shield stacks correctly", %{system: system, generated: generated} do
      # leather + shield: (10 + 1 + 2) base + 2 DEX = 15
      effects =
        item_effects(system, "leather_armor", true) ++ item_effects(system, "shield", true)

      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "armor_class", "total"}] == 15
    end

    test "unequipped armor has no effect on AC", %{system: system, generated: generated} do
      effects = item_effects(system, "plate", false)
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "armor_class", "total"}] == 12
    end
  end

  describe "spellcasting stat nodes integration" do
    setup do
      {:ok, loader_data} = Loader.load(dnd_path())
      {:ok, system} = Graph.build(loader_data)

      generated = %{
        {"ability", "strength", "base_score"} => 10,
        {"ability", "dexterity", "base_score"} => 10,
        {"ability", "constitution", "base_score"} => 10,
        {"ability", "wisdom", "base_score"} => 16,
        {"ability", "intelligence", "base_score"} => 14,
        {"ability", "charisma", "base_score"} => 12
      }

      # WIS mod = +3, INT mod = +2, CHA mod = +1, proficiency bonus = +2

      %{system: system, generated: generated}
    end

    defp class_effects(system, class_id) do
      Enum.filter(system.effects, fn
        %{source: {"class", id}} -> id == class_id
        _ -> false
      end)
    end

    test "non-spellcaster: spellcasting_ability_modifier is 0, dc and bonus still resolve",
         %{system: system, generated: generated} do
      # Fighter has no spellcasting contribution
      effects = class_effects(system, "fighter")
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "spellcasting_ability_modifier", "value"}] == 0
      assert resolved[{"character_trait", "spell_save_dc", "score"}] == 10
      assert resolved[{"character_trait", "spell_attack_bonus", "bonus"}] == 2
    end

    test "wizard uses Intelligence", %{system: system, generated: generated} do
      effects = class_effects(system, "wizard")
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      # INT mod = +2; DC = 8 + 2 + 2 = 12; attack = 2 + 2 = 4
      assert resolved[{"character_trait", "spellcasting_ability_modifier", "value"}] == 2
      assert resolved[{"character_trait", "spell_save_dc", "score"}] == 12
      assert resolved[{"character_trait", "spell_attack_bonus", "bonus"}] == 4
    end

    test "cleric uses Wisdom", %{system: system, generated: generated} do
      effects = class_effects(system, "cleric")
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      # WIS mod = +3; DC = 8 + 2 + 3 = 13; attack = 2 + 3 = 5
      assert resolved[{"character_trait", "spellcasting_ability_modifier", "value"}] == 3
      assert resolved[{"character_trait", "spell_save_dc", "score"}] == 13
      assert resolved[{"character_trait", "spell_attack_bonus", "bonus"}] == 5
    end

    test "bard uses Charisma", %{system: system, generated: generated} do
      effects = class_effects(system, "bard")
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      # CHA mod = +1; DC = 8 + 2 + 1 = 11; attack = 2 + 1 = 3
      assert resolved[{"character_trait", "spellcasting_ability_modifier", "value"}] == 1
      assert resolved[{"character_trait", "spell_save_dc", "score"}] == 11
      assert resolved[{"character_trait", "spell_attack_bonus", "bonus"}] == 3
    end
  end

  describe "spell slots integration" do
    setup do
      {:ok, loader_data} = Loader.load(dnd_path())
      {:ok, system} = Graph.build(loader_data)

      generated = %{
        {"ability", "strength", "base_score"} => 10,
        {"ability", "dexterity", "base_score"} => 10,
        {"ability", "constitution", "base_score"} => 10,
        {"ability", "wisdom", "base_score"} => 10,
        {"ability", "intelligence", "base_score"} => 10,
        {"ability", "charisma", "base_score"} => 10
      }

      %{system: system, generated: generated}
    end

    defp xp_effect(xp),
      do: %{target: {"character_trait", "experience_points", "total"}, value: xp}

    # level 1 = 0 XP, level 5 = 6500 XP, level 11 = 85000 XP, level 17 = 225000 XP
    defp spell_slots(resolved) do
      for n <- 1..9 do
        resolved[{"character_trait", "spell_slots", "level_#{n}"}]
      end
    end

    test "non-caster has no spell slots at any level", %{system: system, generated: generated} do
      effects = class_effects(system, "fighter") ++ [xp_effect(6500)]
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert spell_slots(resolved) == [0, 0, 0, 0, 0, 0, 0, 0, 0]
    end

    test "full caster (wizard) level 1: 2 first-level slots only",
         %{system: system, generated: generated} do
      effects = class_effects(system, "wizard")
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert spell_slots(resolved) == [2, 0, 0, 0, 0, 0, 0, 0, 0]
    end

    test "full caster (wizard) level 5: 4/3/2 slots for levels 1-3",
         %{system: system, generated: generated} do
      effects = class_effects(system, "wizard") ++ [xp_effect(6500)]
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert spell_slots(resolved) == [4, 3, 2, 0, 0, 0, 0, 0, 0]
    end

    test "full caster (wizard) level 11: gains 6th-level slots",
         %{system: system, generated: generated} do
      effects = class_effects(system, "wizard") ++ [xp_effect(85_000)]
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert spell_slots(resolved) == [4, 3, 3, 3, 2, 1, 0, 0, 0]
    end

    test "half caster (paladin) level 1: no spell slots",
         %{system: system, generated: generated} do
      effects = class_effects(system, "paladin")
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert spell_slots(resolved) == [0, 0, 0, 0, 0, 0, 0, 0, 0]
    end

    test "half caster (paladin) level 5: 4/2 slots for levels 1-2",
         %{system: system, generated: generated} do
      effects = class_effects(system, "paladin") ++ [xp_effect(6500)]
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert spell_slots(resolved) == [4, 2, 0, 0, 0, 0, 0, 0, 0]
    end
  end

  describe "pact magic integration" do
    setup do
      {:ok, loader_data} = Loader.load(dnd_path())
      {:ok, system} = Graph.build(loader_data)

      generated = %{
        {"ability", "strength", "base_score"} => 10,
        {"ability", "dexterity", "base_score"} => 10,
        {"ability", "constitution", "base_score"} => 10,
        {"ability", "wisdom", "base_score"} => 10,
        {"ability", "intelligence", "base_score"} => 10,
        {"ability", "charisma", "base_score"} => 10
      }

      %{system: system, generated: generated}
    end

    test "warlock level 1: 1 slot at spell level 1", %{system: system, generated: generated} do
      effects = class_effects(system, "warlock")
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "pact_magic", "slot_count"}] == 1
      assert resolved[{"character_trait", "pact_magic", "slot_level"}] == 1
    end

    test "warlock level 5: 2 slots at spell level 3", %{system: system, generated: generated} do
      effects = class_effects(system, "warlock") ++ [xp_effect(6500)]
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "pact_magic", "slot_count"}] == 2
      assert resolved[{"character_trait", "pact_magic", "slot_level"}] == 3
    end

    test "warlock level 11: slot count drops to 3, slot level stays 5",
         %{system: system, generated: generated} do
      effects = class_effects(system, "warlock") ++ [xp_effect(85_000)]
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "pact_magic", "slot_count"}] == 3
      assert resolved[{"character_trait", "pact_magic", "slot_level"}] == 5
    end

    test "non-warlock has 0 pact magic slots", %{system: system, generated: generated} do
      effects = class_effects(system, "wizard")
      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      assert resolved[{"character_trait", "pact_magic", "slot_count"}] == 0
      assert resolved[{"character_trait", "pact_magic", "slot_level"}] == 0
    end
  end

  test "when condition edge cases: numeric truthy/falsy and formula errors" do
    system = minimal_system()
    generated = %{{"attr", "strength", "base_score"} => 16}

    # Non-zero number is truthy
    assert {:ok, r1} =
             Evaluator.evaluate(system, generated, [
               %{target: {"attr", "strength", "total_score"}, value: 2, when: "1"}
             ])

    assert r1[{"attr", "strength", "total_score"}] == 18

    # Zero is falsy
    assert {:ok, r2} =
             Evaluator.evaluate(system, generated, [
               %{target: {"attr", "strength", "total_score"}, value: 2, when: "0"}
             ])

    assert r2[{"attr", "strength", "total_score"}] == 16

    # Formula error propagates
    assert {:error, _} =
             Evaluator.evaluate(system, generated, [
               %{
                 target: {"attr", "strength", "total_score"},
                 value: 2,
                 when: "nonexistent('x').y"
               }
             ])
  end
end
