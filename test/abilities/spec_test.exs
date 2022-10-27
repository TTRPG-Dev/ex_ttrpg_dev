defmodule ExTTRPGDevTest.RuleSystems.Abilities.Spec do
  use ExUnit.Case
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.Abilities.Spec

  test "get names from spec list" do
    %RuleSystems.RuleSystem{abilities: %RuleSystems.Abilities{specs: specs}} =
      RuleSystems.load_system!("dnd_5e_srd")

    names_for_specs = Spec.get_names(specs) |> MapSet.new()

    assert names_for_specs ==
             MapSet.new([
               "strength",
               "dexterity",
               "constitution",
               "wisdom",
               "intellegence",
               "charisma"
             ])
  end

  test "get spec from specs by name" do
    %RuleSystems.RuleSystem{abilities: %RuleSystems.Abilities{specs: specs}} =
      RuleSystems.load_system!("dnd_5e_srd")

    %Spec{name: name} = spec = Enum.random(specs)
    found_spec = Spec.get_spec_by_name(specs, name)
    assert spec == found_spec
  end
end
