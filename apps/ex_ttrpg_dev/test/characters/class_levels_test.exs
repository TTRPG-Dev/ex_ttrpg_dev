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
end
