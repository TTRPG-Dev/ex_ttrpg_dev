defmodule ExTTRPGDevTest.RuleSystems.DnD5eSRDContent do
  @moduledoc """
  Checks that the bundled `dnd_5e_srd` content computes the values the SRD
  states. These tests exercise system *content*, not library mechanics.
  """
  use ExUnit.Case, async: true

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Decision
  alias ExTTRPGDev.Characters.InventoryItem
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystems

  @abilities ~w(strength dexterity constitution intelligence wisdom charisma)

  # XP threshold for each level, from the SRD's Character Advancement table.
  @level_xp %{
    1 => 0,
    2 => 300,
    3 => 900,
    4 => 2_700,
    5 => 6_500,
    6 => 14_000,
    7 => 23_000,
    8 => 34_000,
    9 => 48_000,
    10 => 64_000,
    11 => 85_000,
    12 => 100_000,
    13 => 120_000,
    14 => 140_000,
    15 => 165_000,
    16 => 195_000,
    17 => 225_000,
    18 => 255_000,
    19 => 285_000,
    20 => 305_000
  }

  setup_all do
    {:ok, system: RuleSystems.load_system!("dnd_5e_srd")}
  end

  # Builds a character with every ability base score set to `scores[ability]`
  # (default 10), the given root/scoped decisions, level and equipped items.
  defp character(system, opts) do
    scores = Keyword.get(opts, :scores, %{})
    level = Keyword.get(opts, :level, 1)

    generated =
      Map.new(@abilities, fn a -> {{"ability", a, "base_score"}, Map.get(scores, a, 10)} end)

    inventory =
      opts
      |> Keyword.get(:equipped, [])
      |> Enum.map(fn id ->
        %InventoryItem{concept_type: "equipment", concept_id: id, fields: %{"equipped" => true}}
      end)

    xp = %Effect{
      target: {"character_trait", "experience_points", "total"},
      value: Map.fetch!(@level_xp, level)
    }

    base = Character.gen_character!(system)

    %{
      base
      | generated_values: Map.merge(base.generated_values, generated),
        decisions: Keyword.get(opts, :decisions, []),
        inventory: inventory,
        effects: [xp],
        level_classes: Keyword.get(opts, :level_classes, [])
    }
  end

  defp resolve(system, opts) do
    {_effects, values} = Characters.resolved_state(system, character(system, opts))
    values
  end

  defp root(type, id), do: %Decision{scope: nil, choice: type, selection: id}

  defp node(values, type, id, field), do: Map.fetch!(values, {type, id, field})

  defp ac(values), do: node(values, "character_trait", "armor_class", "total")

  defp class_values(system, class, level, opts \\ []) do
    resolve(system, [decisions: [root("class", class)], level: level] ++ opts)
  end

  describe "armor worn" do
    test "counts equipped body armor, heavy armor and shields", %{system: system} do
      values = resolve(system, equipped: ["plate", "shield"])

      assert values[{"character_trait", "armor_worn", "body"}] == 1
      assert values[{"character_trait", "armor_worn", "heavy"}] == 1
      assert values[{"character_trait", "armor_worn", "shield"}] == 1
    end

    test "is zero with nothing equipped", %{system: system} do
      values = resolve(system, [])

      assert values[{"character_trait", "armor_worn", "body"}] == 0
      assert values[{"character_trait", "armor_worn", "shield"}] == 0
    end
  end

  describe "barbarian" do
    test "Unarmored Defense adds Con to AC without body armor, shield allowed", %{system: system} do
      scores = %{"dexterity" => 14, "constitution" => 16}

      assert ac(class_values(system, "barbarian", 1, scores: scores)) == 15
      assert ac(class_values(system, "barbarian", 1, scores: scores, equipped: ["shield"])) == 17

      assert ac(class_values(system, "barbarian", 1, scores: scores, equipped: ["chain_mail"])) ==
               16
    end

    test "rages and rage damage follow the class table", %{system: system} do
      for {level, rages, damage} <- [{1, 2, 2}, {3, 3, 2}, {9, 4, 3}, {16, 5, 4}, {17, 6, 4}] do
        values = class_values(system, "barbarian", level)
        assert node(values, "class", "barbarian", "rages") == rages
        assert node(values, "class", "barbarian", "rage_damage") == damage
      end

      assert node(class_values(system, "barbarian", 19), "class", "barbarian", "rages_unlimited") ==
               false

      assert node(class_values(system, "barbarian", 20), "class", "barbarian", "rages_unlimited")
    end

    test "Fast Movement adds 10 ft from 5th level unless in heavy armor", %{system: system} do
      speed = &node(&1, "character_trait", "speed", "amount")

      assert speed.(class_values(system, "barbarian", 4)) == 0
      assert speed.(class_values(system, "barbarian", 5)) == 10
      assert speed.(class_values(system, "barbarian", 5, equipped: ["chain_shirt"])) == 10
      assert speed.(class_values(system, "barbarian", 5, equipped: ["plate"])) == 0
    end

    test "Primal Champion raises Strength and Constitution by 4 at 20th level", %{system: system} do
      values = class_values(system, "barbarian", 20)

      assert node(values, "ability", "strength", "total_score") == 14
      assert node(values, "ability", "constitution", "total_score") == 14

      assert node(class_values(system, "barbarian", 19), "ability", "strength", "total_score") ==
               10
    end
  end

  describe "bard" do
    test "Bardic Inspiration die and uses follow the class table", %{system: system} do
      for {level, die} <- [{1, 6}, {5, 8}, {10, 10}, {15, 12}] do
        assert node(
                 class_values(system, "bard", level),
                 "class",
                 "bard",
                 "bardic_inspiration_die"
               ) ==
                 die
      end

      uses =
        &node(
          class_values(system, "bard", 1, scores: %{"charisma" => &1}),
          "class",
          "bard",
          "bardic_inspiration_uses"
        )

      assert uses.(16) == 3
      assert uses.(8) == 1
    end

    test "Song of Rest starts at 2nd level", %{system: system} do
      assert node(class_values(system, "bard", 1), "class", "bard", "song_of_rest_die") == 0
      assert node(class_values(system, "bard", 2), "class", "bard", "song_of_rest_die") == 6
      assert node(class_values(system, "bard", 17), "class", "bard", "song_of_rest_die") == 12
    end
  end

  describe "cleric" do
    test "Channel Divinity uses and Destroy Undead CR follow the class table", %{system: system} do
      for {level, uses, cr} <- [
            {1, 0, 0},
            {2, 1, 0},
            {5, 1, 0.5},
            {6, 2, 0.5},
            {17, 2, 4},
            {18, 3, 4}
          ] do
        values = class_values(system, "cleric", level)
        assert node(values, "class", "cleric", "channel_divinity_uses") == uses
        assert node(values, "class", "cleric", "destroy_undead_cr") == cr
      end
    end
  end

  describe "druid" do
    test "Wild Shape limits follow the Beast Shapes table", %{system: system} do
      at4 = class_values(system, "druid", 4)
      assert node(at4, "class", "druid", "wild_shape_max_cr") == 0.5
      assert node(at4, "class", "druid", "wild_shape_swim") == 1
      assert node(at4, "class", "druid", "wild_shape_fly") == 0

      at8 = class_values(system, "druid", 8)
      assert node(at8, "class", "druid", "wild_shape_max_cr") == 1
      assert node(at8, "class", "druid", "wild_shape_fly") == 1
    end

    test "Wild Shape uses start at 2nd level and become unlimited at 20th", %{system: system} do
      assert node(class_values(system, "druid", 1), "class", "druid", "wild_shape_uses") == 0
      assert node(class_values(system, "druid", 2), "class", "druid", "wild_shape_uses") == 2
      refute node(class_values(system, "druid", 19), "class", "druid", "wild_shape_unlimited")
      assert node(class_values(system, "druid", 20), "class", "druid", "wild_shape_unlimited")
    end
  end

  describe "fighter" do
    test "Action Surge, Indomitable and Extra Attack follow the class table", %{system: system} do
      for {level, surge, indomitable, attacks} <- [
            {1, 0, 0, 1},
            {2, 1, 0, 1},
            {5, 1, 0, 2},
            {9, 1, 1, 2},
            {11, 1, 1, 3},
            {17, 2, 3, 3},
            {20, 2, 3, 4}
          ] do
        values = class_values(system, "fighter", level)
        assert node(values, "class", "fighter", "action_surge_uses") == surge
        assert node(values, "class", "fighter", "indomitable_uses") == indomitable
        assert node(values, "class", "fighter", "attacks_per_action") == attacks
      end
    end

    test "Second Wind heals 1d10 + fighter level", %{system: system} do
      assert node(class_values(system, "fighter", 7), "class", "fighter", "second_wind_bonus") ==
               7
    end

    test "Champion critical range widens at 3rd and 15th level", %{system: system} do
      for {level, range} <- [{2, 20}, {3, 19}, {15, 18}] do
        assert node(class_values(system, "fighter", level), "class", "champion", "critical_range") ==
                 range
      end
    end
  end

  describe "monk" do
    test "Unarmored Defense adds Wis to AC without armor or shield", %{system: system} do
      scores = %{"dexterity" => 14, "wisdom" => 16}

      assert ac(class_values(system, "monk", 1, scores: scores)) == 15
      assert ac(class_values(system, "monk", 1, scores: scores, equipped: ["shield"])) == 14
    end

    test "Unarmored Movement applies only without armor or shield", %{system: system} do
      speed = &node(&1, "character_trait", "speed", "amount")

      assert speed.(class_values(system, "monk", 1)) == 0
      assert speed.(class_values(system, "monk", 6)) == 15
      assert speed.(class_values(system, "monk", 18)) == 30
      assert speed.(class_values(system, "monk", 6, equipped: ["shield"])) == 0
    end

    test "Martial Arts die, ki points and ki save DC", %{system: system} do
      for {level, die, ki} <- [{1, 4, 0}, {2, 4, 2}, {5, 6, 5}, {11, 8, 11}, {17, 10, 17}] do
        values = class_values(system, "monk", level)
        assert node(values, "class", "monk", "martial_arts_die") == die
        assert node(values, "class", "monk", "ki_points") == ki
      end

      values = class_values(system, "monk", 1, scores: %{"wisdom" => 16})
      assert node(values, "class", "monk", "ki_save_dc") == 13
    end
  end

  describe "paladin" do
    test "Lay on Hands pool and Divine Sense uses", %{system: system} do
      values = class_values(system, "paladin", 3, scores: %{"charisma" => 14})

      assert node(values, "class", "paladin", "lay_on_hands_pool") == 15
      assert node(values, "class", "paladin", "divine_sense_uses") == 3
    end

    test "Aura of Protection adds Cha (min +1) to saves from 6th level", %{system: system} do
      dex_save = &node(&1, "saving_throw", "dexterity", "modifier")

      assert dex_save.(class_values(system, "paladin", 5, scores: %{"charisma" => 14})) == 0
      assert dex_save.(class_values(system, "paladin", 6, scores: %{"charisma" => 14})) == 2
      assert dex_save.(class_values(system, "paladin", 6, scores: %{"charisma" => 8})) == 1

      at18 = class_values(system, "paladin", 18)
      assert node(at18, "class", "paladin", "aura_range") == 30
    end
  end

  describe "ranger" do
    test "favored enemies and terrains grow at the class-table levels", %{system: system} do
      for {level, enemies, terrains} <- [{1, 1, 1}, {6, 2, 2}, {10, 2, 3}, {14, 3, 3}] do
        values = class_values(system, "ranger", level)
        assert node(values, "class", "ranger", "favored_enemies") == enemies
        assert node(values, "class", "ranger", "favored_terrains") == terrains
      end
    end
  end

  describe "rogue" do
    test "Sneak Attack dice are half rogue level, rounded up", %{system: system} do
      for {level, dice} <- [{1, 1}, {2, 1}, {3, 2}, {19, 10}, {20, 10}] do
        assert node(class_values(system, "rogue", level), "class", "rogue", "sneak_attack_dice") ==
                 dice
      end
    end
  end

  describe "sorcerer" do
    test "sorcery points and metamagic known follow the class table", %{system: system} do
      for {level, points, metamagic} <- [
            {1, 0, 0},
            {2, 2, 0},
            {3, 3, 2},
            {10, 10, 3},
            {17, 17, 4}
          ] do
        values = class_values(system, "sorcerer", level)
        assert node(values, "class", "sorcerer", "sorcery_points") == points
        assert node(values, "class", "sorcerer", "metamagic_known") == metamagic
      end
    end

    test "Draconic Resilience: AC 13 + Dex unarmored and +1 HP per level", %{system: system} do
      draconic = [
        root("class", "sorcerer"),
        %Decision{
          scope: {"class", "sorcerer"},
          choice: "subclass",
          selection: "draconic_bloodline"
        }
      ]

      scores = %{"dexterity" => 14}
      hp = &node(&1, "character_trait", "max_hit_points", "points")

      assert ac(resolve(system, decisions: draconic, scores: scores)) == 15

      assert ac(resolve(system, decisions: draconic, scores: scores, equipped: ["leather_armor"])) ==
               13

      plain = class_values(system, "sorcerer", 4)
      with_bloodline = resolve(system, decisions: draconic, level: 4)
      assert hp.(with_bloodline) - hp.(plain) == 4
    end
  end

  describe "warlock" do
    test "invocations known and Mystic Arcanum follow the class table", %{system: system} do
      for {level, invocations, arcanum} <- [
            {1, 0, 0},
            {2, 2, 0},
            {5, 3, 0},
            {11, 5, 6},
            {13, 6, 7},
            {18, 8, 9}
          ] do
        values = class_values(system, "warlock", level)
        assert node(values, "class", "warlock", "invocations_known") == invocations
        assert node(values, "class", "warlock", "mystic_arcanum_level") == arcanum
      end
    end
  end

  describe "wizard" do
    test "Arcane Recovery recovers half wizard level in slot levels, rounded up", %{
      system: system
    } do
      for {level, slots} <- [{1, 1}, {4, 2}, {5, 3}] do
        assert node(
                 class_values(system, "wizard", level),
                 "class",
                 "wizard",
                 "arcane_recovery_levels"
               ) ==
                 slots
      end
    end
  end

  describe "backgrounds" do
    test "Acolyte adds proficiency bonus to Insight and Religion", %{system: system} do
      values = resolve(system, decisions: [root("background", "acolyte")])

      assert node(values, "skill", "insight", "modifier") == 2
      assert node(values, "skill", "religion", "modifier") == 2
      assert node(values, "skill", "arcana", "modifier") == 0
    end
  end

  describe "multiclassing" do
    # fighter 1, barbarian 2, fighter 3: fighter 3 / barbarian 2
    defp fighter_barbarian(system) do
      resolve(system,
        decisions: [root("class", "fighter")],
        level: 5,
        level_classes: ["barbarian", "barbarian", "fighter", "fighter"]
      )
    end

    test "class features follow each class's own level", %{system: system} do
      values = fighter_barbarian(system)

      assert node(values, "class", "fighter", "level") == 3
      assert node(values, "class", "barbarian", "level") == 2
      assert node(values, "class", "fighter", "second_wind_bonus") == 3
      assert node(values, "class", "fighter", "attacks_per_action") == 1
      assert node(values, "class", "barbarian", "rages") == 2
    end

    test "proficiency bonus follows the total level", %{system: system} do
      assert node(fighter_barbarian(system), "character_trait", "proficiency_bonus", "bonus") == 3
    end

    test "a class the character doesn't have resolves its table at level 0", %{system: system} do
      values = fighter_barbarian(system)

      assert node(values, "class", "wizard", "level") == 0
      assert node(values, "class", "wizard", "asi_slots") == 0
    end
  end

  describe "races" do
    test "Elf Keen Senses grants Perception proficiency", %{system: system} do
      values = resolve(system, decisions: [root("race", "elf")])
      assert node(values, "skill", "perception", "modifier") == 2
    end

    test "Half-Orc Menacing grants Intimidation proficiency", %{system: system} do
      values = resolve(system, decisions: [root("race", "half_orc")])
      assert node(values, "skill", "intimidation", "modifier") == 2
    end

    test "Hill Dwarf Dwarven Toughness adds 1 HP per level", %{system: system} do
      hp = &node(&1, "character_trait", "max_hit_points", "points")
      dwarf = [root("race", "dwarf")]

      hill =
        dwarf ++ [%Decision{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"}]

      assert hp.(resolve(system, decisions: hill, level: 5)) -
               hp.(resolve(system, decisions: dwarf, level: 5)) == 5
    end

    test "Half-Elf ability increases and Skill Versatility apply the chosen options",
         %{system: system} do
      scope = {"race", "half_elf"}

      decisions = [
        root("race", "half_elf"),
        %Decision{scope: scope, choice: "ability_increase_1", selection: "strength"},
        %Decision{scope: scope, choice: "ability_increase_2", selection: "wisdom"},
        %Decision{scope: scope, choice: "skill_versatility_1", selection: "stealth"},
        %Decision{scope: scope, choice: "skill_versatility_2", selection: "arcana"}
      ]

      values = resolve(system, decisions: decisions)

      assert node(values, "ability", "strength", "total_score") == 11
      assert node(values, "ability", "wisdom", "total_score") == 11
      assert node(values, "ability", "charisma", "total_score") == 12
      assert node(values, "skill", "stealth", "modifier") == 2
      assert node(values, "skill", "arcana", "modifier") == 2
    end

    test "Dragonborn breath weapon DC and dice, and ancestry resistance", %{system: system} do
      decisions = [
        root("race", "dragonborn"),
        %Decision{scope: {"race", "dragonborn"}, choice: "draconic_ancestry", selection: "red"}
      ]

      values = resolve(system, decisions: decisions, scores: %{"constitution" => 14})
      assert node(values, "race", "dragonborn", "breath_weapon_dc") == 12
      assert node(values, "race", "dragonborn", "breath_weapon_dice") == 2

      for {level, dice} <- [{6, 3}, {11, 4}, {16, 5}] do
        values = resolve(system, decisions: decisions, level: level)
        assert node(values, "race", "dragonborn", "breath_weapon_dice") == dice
      end

      active = Characters.active_concepts(decisions, system.concept_metadata)
      assert MapSet.member?(active, {"draconic_ancestry", "red"})

      assert system.concept_metadata[{"draconic_ancestry", "red"}]["damage_resistances"] ==
               ["fire"]
    end
  end
end
