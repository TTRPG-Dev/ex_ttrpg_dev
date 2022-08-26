defmodule ExRPGTest.RuleSystems.Abilities.ModifierCalculation do
  use ExUnit.Case
  alias ExRPG.RuleSystems.Abilities.ModifierCalculation

  @step_add_5 %ModifierCalculation.Step{order: 0, method: "add", value: 5}
  @step_subtract_3 %ModifierCalculation.Step{order: 2, method: "subtract", value: 3}
  @step_multiply_4 %ModifierCalculation.Step{order: 1, method: "multiply", value: 4}
  @step_divide_2 %ModifierCalculation.Step{order: 3, method: "divide", value: 2}
  @step_round_down %ModifierCalculation.Step{order: 4, method: "round_down"}
  @step_round_up %ModifierCalculation.Step{order: 5, method: "round_up"}

  test "modify score with addition" do
    assert ModifierCalculation.modify_score_by_step(@step_add_5, 5) == 10
  end

  test "modify score with subtraction" do
    assert ModifierCalculation.modify_score_by_step(@step_subtract_3, 10) == 7
  end

  test "modify score with multiplication" do
    assert ModifierCalculation.modify_score_by_step(@step_multiply_4, 7) == 28
  end

  test "modify score with division" do
    assert ModifierCalculation.modify_score_by_step(@step_divide_2, 28) == 14
  end

  test "modify score by rounding down" do
    assert ModifierCalculation.modify_score_by_step(@step_round_down, 5.7) == 5
  end

  test "modify score by rounding up" do
    assert ModifierCalculation.modify_score_by_step(@step_round_up, 5.3) == 6
  end

  test "get modifier for score via calculation steps" do
    steps = [@step_add_5, @step_multiply_4, @step_subtract_3, @step_divide_2, @step_round_down]
    mod_calulator = %ModifierCalculation{steps: steps}
    # 5 + 5 = 10, 10 * 4 = 40, 40 - 3 = 37, 37 / 2 = 18.5, 18.5 rounded down = 18
    assert ModifierCalculation.modifier_for_score(mod_calulator, 5) == 18
  end

  test "get modifier for score via mappings" do
    mapping = [
      %ModifierCalculation.Mapping{ability_value: 1, modifier_value: -2},
      %ModifierCalculation.Mapping{ability_value: 2, modifier_value: -2},
      %ModifierCalculation.Mapping{ability_value: 3, modifier_value: -2},
      %ModifierCalculation.Mapping{ability_value: 4, modifier_value: -1},
      %ModifierCalculation.Mapping{ability_value: 5, modifier_value: -1},
      %ModifierCalculation.Mapping{ability_value: 6, modifier_value: 0},
      %ModifierCalculation.Mapping{ability_value: 7, modifier_value: 1},
      %ModifierCalculation.Mapping{ability_value: 8, modifier_value: 1},
      %ModifierCalculation.Mapping{ability_value: 9, modifier_value: 2},
      %ModifierCalculation.Mapping{ability_value: 10, modifier_value: 2}
    ]

    mod_calulator = %ModifierCalculation{mapping: mapping}
    assert ModifierCalculation.modifier_for_score(mod_calulator, 5) == -1
  end
end
