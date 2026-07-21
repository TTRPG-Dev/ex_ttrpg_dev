defmodule ExTTRPGDevTest.Characters.ResolveProgressionChoice do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystems

  setup do
    system = RuleSystems.load_system!("dnd_5e_srd")

    decisions = [
      %{scope: nil, choice: "class", selection: "wizard"},
      %{scope: nil, choice: "race", selection: "human"},
      %{scope: nil, choice: "background", selection: "soldier"}
    ]

    character = Character.gen_character!(system, decisions)

    character = %{
      character
      | pending_choice_slots: Characters.compute_pending_choice_slots(system, character)
    }

    {:ok, system: system, character: character}
  end

  defp pending_options(system, character, progression_id) do
    {_effects, resolved} = Characters.resolved_state(system, character)

    system
    |> Characters.pending_choices(character, resolved)
    |> Enum.find(&(&1.id == progression_id and not Map.has_key?(&1, :scope_type)))
    |> Map.fetch!(:options)
  end

  test "resolving a valid selection records the decision and adds to inventory", ctx do
    [cantrip | _] = pending_options(ctx.system, ctx.character, "cantrips")

    assert {:ok, updated} =
             Characters.resolve_progression_choice(ctx.system, ctx.character, "cantrips", cantrip)

    assert %{
             scope: {"character_progression", "cantrips"},
             choice: "choice_1",
             selection: ^cantrip
           } = List.last(updated.decisions)

    assert Enum.any?(updated.inventory, &(&1.concept_id == cantrip))
  end

  test "an already-selected concept is no longer a valid option", ctx do
    [cantrip | _] = pending_options(ctx.system, ctx.character, "cantrips")

    {:ok, updated} =
      Characters.resolve_progression_choice(ctx.system, ctx.character, "cantrips", cantrip)

    assert {:error, {:invalid_selection, ^cantrip}} =
             Characters.resolve_progression_choice(ctx.system, updated, "cantrips", cantrip)
  end

  test "a selection outside the valid options is rejected", ctx do
    # fireball is a level 3 spell, never a cantrip option
    assert {:error, {:invalid_selection, "fireball"}} =
             Characters.resolve_progression_choice(
               ctx.system,
               ctx.character,
               "cantrips",
               "fireball"
             )
  end

  test "a selection progression with nothing pending is rejected", ctx do
    # asi_or_feat requires no choices at level 1 (asi_count is 0)
    assert {:error, {:no_pending_choice, "asi_or_feat"}} =
             Characters.resolve_progression_choice(
               ctx.system,
               ctx.character,
               "asi_or_feat",
               "ability_score_improvement"
             )
  end

  test "unknown progression id is rejected", ctx do
    assert {:error, {:unknown_progression, "nonexistent"}} =
             Characters.resolve_progression_choice(ctx.system, ctx.character, "nonexistent", "x")
  end

  test "consumes the pending choice slot for the resolved progression", ctx do
    slots_before =
      Enum.count(ctx.character.pending_choice_slots, &(&1.progression_id == "spells_known"))

    assert slots_before > 0

    [spell | _] = pending_options(ctx.system, ctx.character, "spells_known")

    {:ok, updated} =
      Characters.resolve_progression_choice(ctx.system, ctx.character, "spells_known", spell)

    assert Enum.count(updated.pending_choice_slots, &(&1.progression_id == "spells_known")) ==
             slots_before - 1
  end

  test "value progression applies the value to its effect target", ctx do
    assert {:ok, updated} =
             Characters.resolve_progression_choice(
               ctx.system,
               ctx.character,
               "hp_per_level",
               "rolled",
               7
             )

    assert %Effect{target: {"character_trait", "max_hit_points", "points"}, value: 7} in updated.effects

    assert %{
             scope: {"character_progression", "hp_per_level"},
             choice: "choice_1",
             selection: "rolled"
           } = List.last(updated.decisions)
  end

  test "value progression requires an integer value", ctx do
    resolve_hp = fn value ->
      Characters.resolve_progression_choice(
        ctx.system,
        ctx.character,
        "hp_per_level",
        "rolled",
        value
      )
    end

    assert {:error, :value_required} = resolve_hp.(nil)
    assert {:error, :value_must_be_integer} = resolve_hp.("7")
  end
end
