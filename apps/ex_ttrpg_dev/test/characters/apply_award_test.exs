defmodule ExTTRPGDevTest.Characters.ApplyAward do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystems

  setup do
    system = RuleSystems.load_system!("dnd_5e_srd")
    {:ok, system: system, character: Character.gen_character!(system)}
  end

  defp xp_effect(amount),
    do: %{target: {"character_trait", "experience_points", "total"}, value: amount}

  test "integer award with an explicit value appends the effect and returns the value",
       %{system: system, character: character} do
    assert {:ok, updated, 300} =
             Characters.apply_award(system, character, "experience_points", 300)

    assert xp_effect(300) in updated.effects
  end

  test "integer award without a value is rejected", %{system: system, character: character} do
    assert {:error, {:value_required, "integer"}} =
             Characters.apply_award(system, character, "experience_points", nil)
  end

  test "integer award with a non-integer value is rejected",
       %{system: system, character: character} do
    assert {:error, :value_must_be_integer} =
             Characters.apply_award(system, character, "experience_points", "300")
  end

  test "next_level_xp award computes the XP needed for the next level",
       %{system: system, character: character} do
    # level 1 with no XP: level 2 requires exactly 300 XP
    assert {:ok, updated, 300} = Characters.apply_award(system, character, "level_up", nil)
    assert xp_effect(300) in updated.effects
  end

  test "next_level_xp award prefers an explicitly supplied value",
       %{system: system, character: character} do
    assert {:ok, updated, 42} = Characters.apply_award(system, character, "level_up", 42)
    assert xp_effect(42) in updated.effects
  end

  test "next_level_xp award at max level returns :max_level",
       %{system: system, character: character} do
    character = %{character | effects: [xp_effect(305_000)]}
    assert {:error, :max_level} = Characters.apply_award(system, character, "level_up", nil)
  end

  test "unknown award id is rejected", %{system: system, character: character} do
    assert {:error, {:unknown_award, "nonexistent"}} =
             Characters.apply_award(system, character, "nonexistent", 1)
  end

  test "recomputes pending choice slots for the awarded state", %{system: system} do
    decisions = [%{scope: nil, choice: "class", selection: "wizard"}]
    character = Character.gen_character!(system, decisions)

    character = %{
      character
      | pending_choice_slots: Characters.compute_pending_choice_slots(system, character)
    }

    # 6500 XP puts the wizard at level 5, unlocking additional spells_known slots
    assert {:ok, updated, 6500} =
             Characters.apply_award(system, character, "experience_points", 6500)

    assert updated.pending_choice_slots ==
             Characters.compute_pending_choice_slots(system, updated)

    assert length(updated.pending_choice_slots) > length(character.pending_choice_slots)
  end
end
