defmodule ExTTRPGDevTest.Characters.Resolution do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystems

  describe "auto_resolve_pending/2" do
    setup do
      system = RuleSystems.load_system!("dnd_5e_srd")
      decisions = Characters.random_decisions(system)
      character = Character.gen_character!(system, decisions)
      slots = Characters.compute_pending_choice_slots(system, character)
      character = %{character | pending_choice_slots: slots}
      %{system: system, character: character}
    end

    test "clears all level-1 pending choices for a fresh character", %{
      system: system,
      character: character
    } do
      resolved_character = Characters.auto_resolve_pending(system, character)

      all_effects = Characters.active_effects(system, resolved_character)

      resolved =
        ExTTRPGDev.RuleSystem.Evaluator.evaluate!(
          system,
          resolved_character.generated_values,
          all_effects
        )

      choices = Characters.pending_choices(system, resolved_character, resolved)

      level_1_pending =
        Enum.filter(choices, fn c ->
          c.type == :pending and c[:earned_at_level] in [nil, 1]
        end)

      assert level_1_pending == []
    end

    test "is a no-op when called again after all level-1 choices are resolved", %{
      system: system,
      character: character
    } do
      resolved_once = Characters.auto_resolve_pending(system, character)
      resolved_twice = Characters.auto_resolve_pending(system, resolved_once)
      assert resolved_once == resolved_twice
    end

    test "selection progressions add decisions pointing to valid concepts", %{
      system: system,
      character: character
    } do
      resolved_character = Characters.auto_resolve_pending(system, character)

      resolved_character.decisions
      |> Enum.filter(fn d -> match?({"character_progression", _}, d.scope) end)
      |> Enum.each(fn decision ->
        {"character_progression", prog_id} = decision.scope
        meta = system.concept_metadata[{"character_progression", prog_id}]

        if meta && Map.has_key?(meta, "type") do
          concept_type = meta["type"]

          assert system.concept_metadata[{concept_type, decision.selection}] != nil,
                 "selection #{inspect(decision.selection)} not found in #{concept_type} concepts"
        end
      end)
    end
  end

  describe "random_resolve_all/2" do
    setup do
      system = RuleSystems.load_system!("dnd_5e_srd")
      decisions = Characters.random_decisions(system)
      character = Character.gen_character!(system, decisions)
      slots = Characters.compute_pending_choice_slots(system, character)

      character =
        Characters.auto_resolve_pending(system, %{character | pending_choice_slots: slots})

      # Award XP to level 2 to generate HP pending choices
      xp_target = {"character_trait", "experience_points", "total"}

      character = %{
        character
        | effects: character.effects ++ [%Effect{target: xp_target, value: 300}]
      }

      slots = Characters.compute_pending_choice_slots(system, character)
      character = %{character | pending_choice_slots: slots}

      %{system: system, character: character}
    end

    test "returns updated character with no pending choices", %{
      system: system,
      character: character
    } do
      {resolved, _resolutions} = Characters.random_resolve_all(system, character)

      all_effects = Characters.active_effects(system, resolved)

      resolved_map =
        ExTTRPGDev.RuleSystem.Evaluator.evaluate!(system, resolved.generated_values, all_effects)

      choices = Characters.pending_choices(system, resolved, resolved_map)

      assert Enum.filter(choices, &(&1.type == :pending)) == []
    end

    test "returns a resolution entry for each resolved choice", %{
      system: system,
      character: character
    } do
      all_effects = Characters.active_effects(system, character)

      resolved_map =
        ExTTRPGDev.RuleSystem.Evaluator.evaluate!(system, character.generated_values, all_effects)

      pending_before =
        Enum.filter(
          Characters.pending_choices(system, character, resolved_map),
          &(&1.type == :pending)
        )

      {_resolved, resolutions} = Characters.random_resolve_all(system, character)

      assert length(resolutions) >= length(pending_before)
    end

    test "selection resolutions carry a concept_type and selection_id", %{
      system: system,
      character: character
    } do
      {_resolved, resolutions} = Characters.random_resolve_all(system, character)

      selection_resolutions = Enum.filter(resolutions, &(&1.selection_id != nil))

      Enum.each(selection_resolutions, fn r ->
        assert r.concept_type != nil
        assert system.concept_metadata[{r.concept_type, r.selection_id}] != nil
      end)
    end

    test "value resolutions carry a rolled_value and method", %{
      system: system,
      character: character
    } do
      {_resolved, resolutions} = Characters.random_resolve_all(system, character)

      value_resolutions = Enum.filter(resolutions, &(&1.rolled_value != nil))

      Enum.each(value_resolutions, fn r ->
        assert is_integer(r.rolled_value) and r.rolled_value > 0
        assert r.method in ["rolled", "average"]
      end)
    end
  end
end
