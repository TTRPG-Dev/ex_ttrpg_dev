defmodule ExTTRPGDevTest.Characters.ClassLevels do
  use ExUnit.Case, async: true

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDevTest.ClassLevelsFixture, as: Fixture

  # Level thresholds in the fixture: 1 at 0 XP, then one level per 100 XP.
  defp xp_for(level), do: (level - 1) * 100

  setup_all do
    {:ok, system: Fixture.system!()}
  end

  defp resolved(system, character) do
    {_effects, resolved} = Characters.resolved_state(system, character)
    resolved
  end

  describe "class level nodes" do
    test "a single-class character's class level is the total level", %{system: system} do
      resolved = resolved(system, Fixture.character("fighter", xp: xp_for(3)))

      assert resolved[{"class", "fighter", "level"}] == 3
      assert resolved[{"class", "wizard", "level"}] == 0
      assert resolved[{"class", "fighter", "second_wind_bonus"}] == 3
    end

    # {level reached, level_classes, expected fighter level, expected wizard level}
    @splits [
      {"recorded levels go to the class they name", 4, ["wizard", "fighter", "wizard"], 2, 2},
      {"levels beyond the record go to the first class", 5, ["wizard"], 4, 1},
      {"recorded levels the character hasn't reached don't count", 2, ["fighter", "wizard"], 2, 0}
    ]

    for {name, level, record, fighter, wizard} <- @splits do
      @level level
      @record record
      @fighter fighter
      @wizard wizard

      test name, %{system: system} do
        character = Fixture.character("fighter", xp: xp_for(@level), level_classes: @record)
        resolved = resolved(system, character)

        assert resolved[{"class", "fighter", "level"}] == @fighter
        assert resolved[{"class", "wizard", "level"}] == @wizard
      end
    end

    test "a character without a class has no class levels", %{system: system} do
      character = %{Fixture.character("fighter") | decisions: []}
      resolved = resolved(system, character)

      assert resolved[{"class", "fighter", "level"}] == 0
    end
  end

  describe "class_levels/2" do
    test "maps each class the character has to its level", %{system: system} do
      character = Fixture.character("fighter", xp: xp_for(4), level_classes: ["wizard"])

      assert {:ok, %{"fighter" => 3, "wizard" => 1}} == Characters.class_levels(system, character)
    end

    test "a single-class character has one entry", %{system: system} do
      assert {:ok, %{"wizard" => 1}} ==
               Characters.class_levels(system, Fixture.character("wizard"))
    end

    test "errors for a system without class levels" do
      system = RuleSystems.load_system!("dnd_5e_srd")

      assert {:error, :class_levels_not_enabled} =
               Characters.class_levels(system, %Character{effects: []})
    end
  end

  describe "level_up/3" do
    @strong %{"strength" => 13}
    @strong_and_smart %{"strength" => 13, "intelligence" => 13}

    test "gains a level in the first class by default", %{system: system} do
      character = Fixture.character("fighter", xp: xp_for(2))

      assert {:ok, leveled} = Characters.level_up(system, character)
      assert leveled.level_classes == ["fighter", "fighter"]
      assert {:ok, %{"fighter" => 3}} == Characters.class_levels(system, leveled)
    end

    test "records the named class", %{system: system} do
      character = Fixture.character("fighter", scores: @strong_and_smart)

      assert {:ok, leveled} = Characters.level_up(system, character, class: "wizard")
      assert leveled.level_classes == ["wizard"]
      assert {:ok, %{"fighter" => 1, "wizard" => 1}} == Characters.class_levels(system, leveled)
    end

    test "writes down unrecorded levels as the first class's", %{system: system} do
      character = Fixture.character("fighter", xp: xp_for(3), scores: @strong_and_smart)

      assert {:ok, leveled} = Characters.level_up(system, character, class: "wizard")
      assert leveled.level_classes == ["fighter", "fighter", "wizard"]
    end

    test "can level a class the character already has", %{system: system} do
      character =
        Fixture.character("fighter", xp: xp_for(2), level_classes: ["wizard"], scores: @strong)

      assert {:ok, leveled} = Characters.level_up(system, character, class: "wizard")
      assert {:ok, %{"fighter" => 1, "wizard" => 2}} == Characters.class_levels(system, leveled)
    end

    test "rejects a new class whose prerequisite isn't met", %{system: system} do
      character = Fixture.character("fighter", scores: @strong)

      assert {:error, {:multiclass_prerequisite_not_met, "wizard"}} =
               Characters.level_up(system, character, class: "wizard")
    end

    test "rejects a new class when a held class's prerequisite isn't met", %{system: system} do
      character = Fixture.character("fighter", scores: %{"intelligence" => 13})

      assert {:error, {:multiclass_prerequisite_not_met, "fighter"}} =
               Characters.level_up(system, character, class: "wizard")
    end

    test "rejects a class without a multiclass table", %{system: system} do
      character = Fixture.character("fighter", scores: @strong_and_smart)

      assert {:error, {:not_multiclassable, "champion"}} =
               Characters.level_up(system, character, class: "champion")
    end

    test "rejects an unknown class", %{system: system} do
      assert {:error, {:unknown_class, "bard"}} =
               Characters.level_up(system, Fixture.character("fighter"), class: "bard")
    end

    test "rejects a character without a class", %{system: system} do
      character = %{Fixture.character("fighter") | decisions: []}
      assert {:error, :no_class} = Characters.level_up(system, character)
    end

    test "reports :max_level at the highest level", %{system: system} do
      assert {:error, :max_level} =
               Characters.level_up(system, Fixture.character("fighter", xp: xp_for(5)))
    end

    test "levels a character in a system without class levels" do
      system = RuleSystems.load_system!("dnd_5e_srd")
      character = Character.gen_character!(system)

      assert {:ok, leveled} = Characters.level_up(system, character)
      assert {:ok, 600, 3} = Characters.xp_to_next_level(system, leveled)
      assert leveled.level_classes == []
    end

    test "rejects :class in a system without class levels" do
      system = RuleSystems.load_system!("dnd_5e_srd")
      character = %Character{effects: [], decisions: [], generated_values: %{}}

      assert {:error, :class_levels_not_enabled} =
               Characters.level_up(system, character, class: "fighter")
    end
  end

  describe "additional classes" do
    defp max_hp(system, character),
      do: resolved(system, character)[{"character_trait", "max_hit_points", "points"}]

    test "are active", %{system: system} do
      character = Fixture.character("fighter", xp: xp_for(2), level_classes: ["wizard"])

      assert MapSet.member?(Characters.active_concepts(system, character), {"class", "wizard"})
    end

    test "don't apply first_class_only contributes", %{system: system} do
      # fighter: 10 (first class only) + 1; wizard's 6 is first class only
      character = Fixture.character("fighter", xp: xp_for(2), level_classes: ["wizard"])
      assert max_hp(system, character) == 11
    end

    test "apply their other contributes", %{system: system} do
      # wizard first: 6; fighter's 1 applies, its 10 doesn't
      character = Fixture.character("wizard", xp: xp_for(2), level_classes: ["fighter"])
      assert max_hp(system, character) == 7
    end

    test "a first class applies its first_class_only contributes", %{system: system} do
      assert max_hp(system, Fixture.character("wizard")) == 6
    end
  end
end
