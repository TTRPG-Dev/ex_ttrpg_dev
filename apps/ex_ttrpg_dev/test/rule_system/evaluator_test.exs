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
    test "evaluate full dnd_5e_srd with known scores" do
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

      assert {:ok, resolved} = Evaluator.evaluate(system, generated)

      # Verify modifiers: floor((score - 10) / 2)
      assert resolved[{"ability", "strength", "modifier"}] == 3
      assert resolved[{"ability", "dexterity", "modifier"}] == 2
      assert resolved[{"ability", "constitution", "modifier"}] == 2
      assert resolved[{"ability", "wisdom", "modifier"}] == 1
      assert resolved[{"ability", "intelligence", "modifier"}] == 0
      assert resolved[{"ability", "charisma", "modifier"}] == -1

      # Verify skills inherit their ability modifier
      assert resolved[{"skill", "athletics", "modifier"}] == 3
      assert resolved[{"skill", "acrobatics", "modifier"}] == 2
      assert resolved[{"skill", "arcana", "modifier"}] == 0

      # Verify proficiency bonus base value
      assert resolved[{"character_trait", "proficiency_bonus", "bonus"}] == 2

      # Verify saving throws inherit their ability modifier
      assert resolved[{"saving_throw", "strength", "modifier"}] == 3
      assert resolved[{"saving_throw", "dexterity", "modifier"}] == 2
      assert resolved[{"saving_throw", "constitution", "modifier"}] == 2
      assert resolved[{"saving_throw", "wisdom", "modifier"}] == 1
      assert resolved[{"saving_throw", "intelligence", "modifier"}] == 0
      assert resolved[{"saving_throw", "charisma", "modifier"}] == -1
    end

    test "saving throw modifier increases when proficiency is applied as an effect" do
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

      # Proficiency bonus of +2 applied to strength saving throw
      effects = [%{target: {"saving_throw", "strength", "modifier"}, value: 2}]

      assert {:ok, resolved} = Evaluator.evaluate(system, generated, effects)
      # strength modifier is 3, plus proficiency bonus of 2
      assert resolved[{"saving_throw", "strength", "modifier"}] == 5
      # other saving throws are unaffected
      assert resolved[{"saving_throw", "dexterity", "modifier"}] == 2
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
