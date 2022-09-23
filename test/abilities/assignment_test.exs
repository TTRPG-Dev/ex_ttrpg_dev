defmodule ExTTRPGDevTest.RuleSystems.Abilities.Assignment do
  use ExUnit.Case
  alias ExTTRPGDev.RuleSystems.Abilities.Assignment

  doctest Assignment, except: [default_assignment: 1]

  test "default assignment is fist method when no default defined" do
    methods = [
      %Assignment.RollingMethod{name: "hard", dice: "3d6"},
      %Assignment.RollingMethod{name: "standard", dice: "4d6", special: "drop_lowest"}
    ]

    default_method = Assignment.default_assignment(%Assignment{rolling_methods: methods})
    assert default_method.name == "hard"
  end

  test "default assignment returned when defined" do
    methods = [
      %Assignment.RollingMethod{name: "hard", dice: "3d6"},
      %Assignment.RollingMethod{
        name: "standard",
        dice: "4d6",
        special: "drop_lowest",
        default: true
      }
    ]

    default_method = Assignment.default_assignment(%Assignment{rolling_methods: methods})
    assert default_method.name == "standard"
  end
end
