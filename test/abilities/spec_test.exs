defmodule ExRPGTest.RuleSystems.Abilities.Spec do
  use ExUnit.Case
  alias ExRPG.RuleSystems
  alias ExRPG.RuleSystems.Abilities.Spec

  test "get names from spec list" do
    %RuleSystems.RuleSystem{abilities: %RuleSystems.Abilities{specs: specs}}= RuleSystems.load_system!("dnd_5e_srd")
    names_for_specs = Spec.get_names(specs) |> MapSet.new()
    assert names_for_specs == MapSet.new(["strength", "dexterity", "constitution", "wisdom", "intellegence", "charisma"])
  end

end
