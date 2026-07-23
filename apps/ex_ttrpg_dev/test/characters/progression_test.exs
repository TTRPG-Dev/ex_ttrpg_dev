defmodule ExTTRPGDevTest.Characters.Progression do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, Decision}
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystems

  defp minimal_system(effects, concept_metadata) do
    %ExTTRPGDev.RuleSystems.LoadedSystem{
      module: nil,
      graph: nil,
      nodes: %{},
      rolling_methods: %{},
      effects: effects,
      concept_metadata: concept_metadata
    }
  end

  defp minimal_character(decisions) do
    %Character{
      name: "Test",
      generated_values: %{},
      effects: [],
      decisions: decisions,
      metadata: %ExTTRPGDev.Characters.Metadata{slug: "test", rule_system: "dnd_5e_srd"}
    }
  end

  describe "pending_choices/3" do
    @level_binding %{{"character_trait", "character_level", "level"} => 3}

    @hp_progression %{
      "name" => "Hit Points",
      "required_count" => "character_trait('character_level').level - 1",
      "effect_target" => "character_trait('max_hit_points').points"
    }

    @spend_xp_progression %{
      "name" => "Spend XP",
      "available_when" => "character_trait('experience_points').total",
      "effect_target" => "skill('athletics').modifier"
    }

    defp progression_system(progressions) do
      minimal_system(
        [],
        Map.new(progressions, fn {id, meta} ->
          {{"character_progression", id}, meta}
        end)
      )
    end

    test "returns empty list when no character_progression concepts exist" do
      system = minimal_system([], %{})
      assert Characters.pending_choices(system, minimal_character([]), %{}) == []
    end

    test "returns a pending entry when required slots exceed decisions made" do
      system = progression_system(%{"hp_per_level" => @hp_progression})
      # level 3 → required 2, decisions made 0 → 2 pending
      [entry] = Characters.pending_choices(system, minimal_character([]), @level_binding)
      assert entry.type == :pending
      assert entry.id == "hp_per_level"
      assert entry.name == "Hit Points"
      assert entry.count == 2
      assert entry.effect_target == "character_trait('max_hit_points').points"
    end

    test "reduces pending count by decisions already made for that progression" do
      system = progression_system(%{"hp_per_level" => @hp_progression})

      decisions = [
        %Decision{
          scope: {"character_progression", "hp_per_level"},
          choice: "choice_1",
          selection: "rolled"
        }
      ]

      # level 3 → required 2, made 1 → 1 pending
      [entry] = Characters.pending_choices(system, minimal_character(decisions), @level_binding)
      assert entry.count == 1
    end

    test "returns empty when all required slots are filled" do
      system = progression_system(%{"hp_per_level" => @hp_progression})

      decisions = [
        %Decision{
          scope: {"character_progression", "hp_per_level"},
          choice: "choice_1",
          selection: "rolled"
        },
        %Decision{
          scope: {"character_progression", "hp_per_level"},
          choice: "choice_2",
          selection: "average"
        }
      ]

      # level 3 → required 2, made 2 → empty
      assert Characters.pending_choices(system, minimal_character(decisions), @level_binding) ==
               []
    end

    test "does not count decisions scoped to a different progression" do
      system =
        progression_system(%{"hp_per_level" => @hp_progression, "other" => @hp_progression})

      decisions = [
        %Decision{
          scope: {"character_progression", "other"},
          choice: "choice_1",
          selection: "rolled"
        }
      ]

      result = Characters.pending_choices(system, minimal_character(decisions), @level_binding)
      hp_entry = Enum.find(result, &(&1.id == "hp_per_level"))
      assert hp_entry.count == 2
    end

    test "returns empty for required_count when formula binding is missing" do
      system = progression_system(%{"hp_per_level" => @hp_progression})
      assert Characters.pending_choices(system, minimal_character([]), %{}) == []
    end

    test "returns an available entry when available_when is truthy" do
      system = progression_system(%{"spend_xp" => @spend_xp_progression})
      resolved = %{{"character_trait", "experience_points", "total"} => 100}
      [entry] = Characters.pending_choices(system, minimal_character([]), resolved)
      assert entry.type == :available
      assert entry.id == "spend_xp"
      assert entry.effect_target == "skill('athletics').modifier"
    end

    test "returns empty when available_when evaluates to 0" do
      system = progression_system(%{"spend_xp" => @spend_xp_progression})
      resolved = %{{"character_trait", "experience_points", "total"} => 0}
      assert Characters.pending_choices(system, minimal_character([]), resolved) == []
    end

    test "returns empty when available_when evaluates to false" do
      progression =
        Map.put(
          @spend_xp_progression,
          "available_when",
          "character_trait('experience_points').total > 0"
        )

      system = progression_system(%{"spend_xp" => progression})
      resolved = %{{"character_trait", "experience_points", "total"} => 0}
      assert Characters.pending_choices(system, minimal_character([]), resolved) == []
    end

    test "returns empty for available_when when formula binding is missing" do
      system = progression_system(%{"spend_xp" => Map.delete(@spend_xp_progression, "name")})
      assert Characters.pending_choices(system, minimal_character([]), %{}) == []
    end

    test "returns empty when progression has neither required_count nor available_when" do
      progression = %{
        "name" => "Inert",
        "effect_target" => "character_trait('max_hit_points').points"
      }

      system = progression_system(%{"inert" => progression})
      assert Characters.pending_choices(system, minimal_character([]), %{}) == []
    end

    test "falls back to id as name when name is not present" do
      progression = Map.delete(@hp_progression, "name")
      system = progression_system(%{"hp_per_level" => progression})
      [entry] = Characters.pending_choices(system, minimal_character([]), @level_binding)
      assert entry.name == "hp_per_level"
    end

    test "resolves roll_reference from the character's active root decision" do
      concept_metadata = %{
        {"character_progression", "hp_per_level"} =>
          Map.put(@hp_progression, "roll_reference", "class.hit_die"),
        {"class", "fighter"} => %{"hit_die" => "d10"}
      }

      system = minimal_system([], concept_metadata)
      decisions = [%Decision{scope: nil, choice: "class", selection: "fighter"}]
      [entry] = Characters.pending_choices(system, minimal_character(decisions), @level_binding)
      assert entry.roll == "d10"
    end

    test "roll is nil when roll_reference has no matching decision on the character" do
      concept_metadata = %{
        {"character_progression", "hp_per_level"} =>
          Map.put(@hp_progression, "roll_reference", "class.hit_die")
      }

      system = minimal_system([], concept_metadata)
      [entry] = Characters.pending_choices(system, minimal_character([]), @level_binding)
      assert entry.roll == nil
    end

    test "roll is nil when no roll_reference is declared" do
      system = progression_system(%{"hp_per_level" => @hp_progression})
      [entry] = Characters.pending_choices(system, minimal_character([]), @level_binding)
      assert entry.roll == nil
    end

    test "returns entries for multiple progressions" do
      other = %{
        "name" => "Other",
        "required_count" => "character_trait('character_level').level - 1",
        "effect_target" => "skill('athletics').modifier"
      }

      system = progression_system(%{"hp_per_level" => @hp_progression, "other" => other})
      result = Characters.pending_choices(system, minimal_character([]), @level_binding)
      assert Enum.map(result, & &1.id) |> Enum.sort() == ["hp_per_level", "other"]
    end

    @cantrip_progression %{
      "name" => "Cantrip",
      "required_count" => "2",
      "type" => "spell",
      "filter" => %{
        "level" => 0,
        "active_in" => %{"field" => "classes", "type" => "class"}
      }
    }

    @spell_meta %{
      {"spell", "fire_bolt"} => %{"level" => 0, "classes" => ["wizard"]},
      {"spell", "mage_hand"} => %{"level" => 0, "classes" => ["wizard"]},
      {"spell", "cure_wounds"} => %{"level" => 1, "classes" => ["cleric"]},
      {"spell", "sacred_flame"} => %{"level" => 0, "classes" => ["cleric"]}
    }

    defp spell_system(progressions, spell_meta) do
      minimal_system(
        [],
        Map.merge(
          Map.new(progressions, fn {id, meta} -> {{"character_progression", id}, meta} end),
          spell_meta
        )
      )
    end

    test "spell progression includes options filtered by level and active class" do
      system = spell_system(%{"cantrips" => @cantrip_progression}, @spell_meta)

      decisions = [%Decision{scope: nil, choice: "class", selection: "wizard"}]
      [entry] = Characters.pending_choices(system, minimal_character(decisions), %{})

      assert entry.id == "cantrips"
      assert entry.count == 2
      assert entry.effect_target == nil
      assert entry.roll == nil
      assert Enum.sort(entry.options) == ["fire_bolt", "mage_hand"]
    end

    test "spell progression returns no options when no class active" do
      system = spell_system(%{"cantrips" => @cantrip_progression}, @spell_meta)

      [entry] = Characters.pending_choices(system, minimal_character([]), %{})

      assert entry.options == []
    end

    test "spell progression with min/max level filter" do
      progression = %{
        "name" => "Spell",
        "required_count" => "2",
        "type" => "spell",
        "filter" => %{
          "min_level" => 1,
          "max_level_node" => "character_trait('max_spell_level').level",
          "active_in" => %{"field" => "classes", "type" => "class"}
        }
      }

      system = spell_system(%{"spells_known" => progression}, @spell_meta)
      resolved = %{{"character_trait", "max_spell_level", "level"} => 1}
      decisions = [%Decision{scope: nil, choice: "class", selection: "cleric"}]

      [entry] = Characters.pending_choices(system, minimal_character(decisions), resolved)

      assert entry.id == "spells_known"
      assert entry.options == ["cure_wounds"]
    end

    test "spell progression uses pending_choice_slots cap instead of resolved max level" do
      spell_meta =
        Map.merge(@spell_meta, %{
          {"spell", "fireball"} => %{"level" => 3, "classes" => ["cleric"]}
        })

      progression = %{
        "name" => "Spell",
        "required_count" => "2",
        "type" => "spell",
        "filter" => %{
          "min_level" => 1,
          "max_level_node" => "character_trait('max_spell_level').level",
          "active_in" => %{"field" => "classes", "type" => "class"}
        }
      }

      system = spell_system(%{"spells_known" => progression}, spell_meta)
      # resolved says max_spell_level = 3, but the slot was earned when only level 1 was available
      resolved = %{{"character_trait", "max_spell_level", "level"} => 3}
      decisions = [%Decision{scope: nil, choice: "class", selection: "cleric"}]

      pending_choice_slots = [
        %{progression_id: "spells_known", earned_at_level: 1, max_level_cap: 1}
      ]

      character = %{minimal_character(decisions) | pending_choice_slots: pending_choice_slots}
      [entry] = Characters.pending_choices(system, character, resolved)

      # fireball (level 3) should be excluded despite resolved allowing level 3
      assert entry.options == ["cure_wounds"]
    end
  end

  describe "compute_pending_choice_slots/2" do
    setup do
      system = RuleSystems.load_system!("dnd_5e_srd")
      attrs = ~w[strength dexterity constitution wisdom intelligence charisma]
      generated = Map.new(attrs, &{{"ability", &1, "base_score"}, 10})

      decisions = [
        %Decision{scope: nil, choice: "class", selection: "sorcerer"},
        %Decision{scope: nil, choice: "race", selection: "human"},
        %Decision{scope: nil, choice: "background", selection: "acolyte"}
      ]

      character = %Character{
        name: "Test",
        generated_values: generated,
        effects: [],
        decisions: decisions,
        pending_choice_slots: [],
        metadata: %ExTTRPGDev.Characters.Metadata{slug: "test_slots", rule_system: "dnd_5e_srd"}
      }

      {:ok, system: system, character: character}
    end

    test "level 1 character gets slots with cap 1 for initial spell choices",
         %{system: system, character: character} do
      slots = Characters.compute_pending_choice_slots(system, character)
      spells_known = Enum.filter(slots, &(&1.progression_id == "spells_known"))

      # sorcerer starts with 2 spells known at level 1
      assert length(spells_known) == 2
      assert Enum.all?(spells_known, &(&1.earned_at_level == 1))
      assert Enum.all?(spells_known, &(&1.max_level_cap == 1))
    end

    test "higher-level slots get appropriate caps reflecting spell access at that level",
         %{system: system, character: character} do
      # XP for level 5 (6500)
      xp_effect = %Effect{target: {"character_trait", "experience_points", "total"}, value: 6500}
      character = %{character | effects: [xp_effect]}

      slots = Characters.compute_pending_choice_slots(system, character)
      spells_known = Enum.filter(slots, &(&1.progression_id == "spells_known"))

      # At level 5, a sorcerer knows 6 spells total; all 6 slots are pending
      assert length(spells_known) == 6

      # Each slot's cap should reflect the max spell level available when that slot was earned:
      # levels 1-2 cap at 1, levels 3-4 cap at 2, level 5 caps at 3
      caps = Enum.map(spells_known, & &1.max_level_cap)
      assert caps == [1, 1, 1, 2, 2, 3]
    end

    test "already-decided slots are excluded from result",
         %{system: system, character: character} do
      # Pre-make one spell decision
      spell_decision = %Decision{
        scope: {"character_progression", "spells_known"},
        choice: "choice_1",
        selection: "fire_bolt"
      }

      character = %{character | decisions: character.decisions ++ [spell_decision]}
      slots = Characters.compute_pending_choice_slots(system, character)
      spells_known = Enum.filter(slots, &(&1.progression_id == "spells_known"))

      # 2 total at level 1, minus 1 decided = 1 remaining
      assert length(spells_known) == 1
    end

    test "returns empty list when no level-capped progressions exist",
         %{system: system, character: character} do
      # Remove all character_progression metadata that has max_level_node
      concept_metadata =
        Map.reject(system.concept_metadata, fn {{type, _id}, meta} ->
          type == "character_progression" and get_in(meta, ["filter", "max_level_node"]) != nil
        end)

      system = %{system | concept_metadata: concept_metadata}
      assert Characters.compute_pending_choice_slots(system, character) == []
    end
  end

  describe "requires filtering in concept_options/4" do
    setup do
      {:ok, system: RuleSystems.load_system!("dnd_5e_srd")}
    end

    defp feat_options(system, str_score) do
      meta = %{"type" => "feat", "required_count" => "1"}
      resolved = %{{"ability", "strength", "total_score"} => str_score}
      Characters.concept_options(meta, system.concept_metadata, MapSet.new(), resolved)
    end

    test "grappler requires STR >= 13 and ability_score_improvement is always available",
         %{system: system} do
      below = feat_options(system, 12)
      refute "grappler" in below
      assert "ability_score_improvement" in below

      assert "grappler" in feat_options(system, 13)
    end
  end

  describe "pending sub-choices from selected progression concepts" do
    @asi_progression %{
      "name" => "ASI or Feat",
      "required_count" => "1",
      "type" => "feat"
    }

    @asi_feat_meta %{
      "name" => "Ability Score Improvement",
      "choices" => %{
        "asi_point_1" => %{
          "type" => "ability",
          "contributes_field" => "total_score",
          "contributes_value" => 1
        },
        "asi_point_2" => %{
          "type" => "ability",
          "contributes_field" => "total_score",
          "contributes_value" => 1
        }
      }
    }

    @ability_meta %{
      {"ability", "strength"} => %{"name" => "Strength"},
      {"ability", "dexterity"} => %{"name" => "Dexterity"}
    }

    defp asi_system do
      concept_metadata =
        Map.merge(
          %{
            {"character_progression", "asi_or_feat"} => @asi_progression,
            {"feat", "ability_score_improvement"} => @asi_feat_meta
          },
          @ability_meta
        )

      %ExTTRPGDev.RuleSystems.LoadedSystem{
        module: nil,
        graph: nil,
        nodes: %{},
        rolling_methods: %{},
        effects: [],
        concept_metadata: concept_metadata
      }
    end

    defp asi_character(decisions) do
      %Character{
        name: "Test",
        generated_values: %{},
        effects: [],
        decisions: decisions,
        metadata: %ExTTRPGDev.Characters.Metadata{slug: "test", rule_system: "dnd_5e_srd"}
      }
    end

    test "no sub-choices when feat has not been selected" do
      system = asi_system()
      choices = Characters.pending_choices(system, asi_character([]), %{})

      sub = Enum.filter(choices, &Map.has_key?(&1, :scope_type))
      assert sub == []
    end

    defp asi_sub_choices do
      decisions = [
        %Decision{
          scope: {"character_progression", "asi_or_feat"},
          choice: "choice_1",
          selection: "ability_score_improvement"
        }
      ]

      choices = Characters.pending_choices(asi_system(), asi_character(decisions), %{})
      Enum.filter(choices, &Map.has_key?(&1, :scope_type))
    end

    test "two sub-choices appear after selecting ability_score_improvement" do
      sub = asi_sub_choices()
      assert length(sub) == 2
      assert Enum.map(sub, & &1.id) |> Enum.sort() == ["asi_point_1", "asi_point_2"]
    end

    test "sub-choices carry correct scope and options" do
      [c | _] = asi_sub_choices()
      assert c.scope_type == "feat"
      assert c.scope_id == "ability_score_improvement"
      assert Enum.sort(c.options) == ["dexterity", "strength"]
    end

    test "sub-choice count decreases as decisions are resolved" do
      decisions = [
        %Decision{
          scope: {"character_progression", "asi_or_feat"},
          choice: "choice_1",
          selection: "ability_score_improvement"
        },
        %Decision{
          scope: {"feat", "ability_score_improvement"},
          choice: "asi_point_1",
          selection: "strength"
        }
      ]

      choices = Characters.pending_choices(asi_system(), asi_character(decisions), %{})

      sub = Enum.filter(choices, &Map.has_key?(&1, :scope_type))
      assert length(sub) == 1
      assert hd(sub).id == "asi_point_2"
    end

    test "no sub-choices remain after all points resolved" do
      decisions = [
        %Decision{
          scope: {"character_progression", "asi_or_feat"},
          choice: "choice_1",
          selection: "ability_score_improvement"
        },
        %Decision{
          scope: {"feat", "ability_score_improvement"},
          choice: "asi_point_1",
          selection: "strength"
        },
        %Decision{
          scope: {"feat", "ability_score_improvement"},
          choice: "asi_point_2",
          selection: "dexterity"
        }
      ]

      choices = Characters.pending_choices(asi_system(), asi_character(decisions), %{})

      sub = Enum.filter(choices, &Map.has_key?(&1, :scope_type))
      assert sub == []
    end
  end
end
