defmodule ExTTRPGDevTest.Characters.XpToNextLevel do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystems

  setup do
    {:ok, system: RuleSystems.load_system!("dnd_5e_srd")}
  end

  defp xp_effect(amount),
    do: %Effect{target: {"character_trait", "experience_points", "total"}, value: amount}

  test "returns xp_needed and next_level for a level 1 character with no xp", %{system: system} do
    character = %Character{effects: []}
    assert {:ok, 300, 2} = Characters.xp_to_next_level(system, character)
  end

  test "accounts for accumulated xp when computing xp still needed", %{system: system} do
    character = %Character{effects: [xp_effect(6500)]}
    # level 5 (6500 XP) → level 6 requires 14000; 14000 - 6500 = 7500 more needed
    assert {:ok, 7500, 6} = Characters.xp_to_next_level(system, character)
  end

  test "returns :max_level for a character at the highest level", %{system: system} do
    character = %Character{effects: [xp_effect(305_000)]}
    assert {:error, :max_level} = Characters.xp_to_next_level(system, character)
  end

  test "returns :no_level_thresholds for a system without a level node", %{system: system} do
    system_no_thresholds = %{system | module: %{system.module | level_node: nil}}
    character = %Character{effects: []}

    assert {:error, :no_level_thresholds} =
             Characters.xp_to_next_level(system_no_thresholds, character)
  end
end
