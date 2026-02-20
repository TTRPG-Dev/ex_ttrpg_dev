defmodule ExTTRPGDev.RuleSystem.EvaluatorTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.{Evaluator, Graph, Loader}

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
      entity_metadata: %{},
      contributions: []
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

  test "evaluate/3 applies active contributions to accumulator" do
    system = minimal_system()
    generated = %{{"attr", "strength", "base_score"} => 16}

    contributions = [%{target: {"attr", "strength", "total_score"}, value: 2}]

    assert {:ok, resolved} = Evaluator.evaluate(system, generated, contributions)
    # total_score = 16 + 2 = 18, modifier = floor((18-10)/2) = 4
    assert resolved[{"attr", "strength", "total_score"}] == 18
    assert resolved[{"attr", "strength", "modifier"}] == 4
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

  test "integration: evaluate full dnd_5e_srd with known scores" do
    {:ok, loader_data} = Loader.load(dnd_path())
    {:ok, system} = Graph.build(loader_data)

    generated = %{
      {"attr", "strength", "base_score"} => 16,
      {"attr", "dexterity", "base_score"} => 14,
      {"attr", "constitution", "base_score"} => 14,
      {"attr", "wisdom", "base_score"} => 12,
      {"attr", "intelligence", "base_score"} => 10,
      {"attr", "charisma", "base_score"} => 8
    }

    assert {:ok, resolved} = Evaluator.evaluate(system, generated)

    # Verify modifiers: floor((score - 10) / 2)
    assert resolved[{"attr", "strength", "modifier"}] == 3
    assert resolved[{"attr", "dexterity", "modifier"}] == 2
    assert resolved[{"attr", "constitution", "modifier"}] == 2
    assert resolved[{"attr", "wisdom", "modifier"}] == 1
    assert resolved[{"attr", "intelligence", "modifier"}] == 0
    assert resolved[{"attr", "charisma", "modifier"}] == -1

    # Verify skills inherit their attribute modifier
    assert resolved[{"skill", "athletics", "modifier"}] == 3
    assert resolved[{"skill", "acrobatics", "modifier"}] == 2
    assert resolved[{"skill", "arcana", "modifier"}] == 0
  end
end
