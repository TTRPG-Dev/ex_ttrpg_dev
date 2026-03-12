defmodule ExTTRPGDevTest.CLI.CharacterDisplay do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.CLI.CharacterDisplay
  alias ExTTRPGDev.RuleSystems

  setup do
    system = RuleSystems.load_system!("dnd_5e_srd")
    character = Character.gen_character!(system)
    {:ok, system: system, character: character}
  end

  test "print/2 outputs the character name", %{system: system, character: character} do
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, character.name)
  end

  test "print/2 shows Abilities section", %{system: system, character: character} do
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "Abilities:")
  end

  test "print/2 shows all six D&D attributes", %{system: system, character: character} do
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)

    for name <- ~w(Strength Dexterity Constitution Wisdom Intelligence Charisma) do
      assert String.contains?(output, name), "Expected #{name} in output"
    end
  end

  test "print/2 shows Skills section", %{system: system, character: character} do
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "Skills:")
  end

  test "print/2 shows the character's race", %{system: system} do
    decisions = [%{scope: nil, choice: "race", selection: "human"}]

    character = %{
      Character.gen_character!(system, decisions)
      | decisions: decisions
    }

    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "Race: Human")
  end

  test "print/2 shows subrace chain for races with subraces", %{system: system} do
    decisions = [
      %{scope: nil, choice: "race", selection: "dwarf"},
      %{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"}
    ]

    character = %{
      Character.gen_character!(system, decisions)
      | decisions: decisions
    }

    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "Race: Dwarf / Hill Dwarf")
  end

  test "print/2 does not show a Languages section header from the concept type loop", %{
    system: system,
    character: character
  } do
    # Languages have no DAG nodes so they never appear via the concept type loop.
    # The fixture character has no race decisions so no language grants appear either.
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    refute String.contains?(output, "Languages:")
  end

  test "print/2 shows fixed language grants from race", %{system: system} do
    decisions = [
      %{scope: nil, choice: "race", selection: "dwarf"},
      %{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"},
      %{scope: {"race", "dwarf"}, choice: "artisans_tool_proficiency", selection: "smiths_tools"}
    ]

    character = %{Character.gen_character!(system, decisions) | decisions: decisions}
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "Languages:")
    assert String.contains?(output, "Common")
    assert String.contains?(output, "Dwarvish")
  end

  test "print/2 includes chosen extra language in Languages line", %{system: system} do
    decisions = [
      %{scope: nil, choice: "race", selection: "human"},
      %{scope: {"race", "human"}, choice: "extra_language", selection: "elvish"}
    ]

    character = %{Character.gen_character!(system, decisions) | decisions: decisions}
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "Elvish")
  end

  test "print/2 shows tool proficiency choice", %{system: system} do
    decisions = [
      %{scope: nil, choice: "race", selection: "dwarf"},
      %{scope: {"race", "dwarf"}, choice: "subrace", selection: "hill_dwarf"},
      %{scope: {"race", "dwarf"}, choice: "artisans_tool_proficiency", selection: "smiths_tools"}
    ]

    character = %{Character.gen_character!(system, decisions) | decisions: decisions}
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "Tool Proficiencies:")
    assert String.contains?(output, "Smith's Tools")
  end

  test "print/2 shows fixed tool proficiency (Rock Gnome)", %{system: system} do
    decisions = [
      %{scope: nil, choice: "race", selection: "gnome"},
      %{scope: {"race", "gnome"}, choice: "subrace", selection: "rock_gnome"}
    ]

    character = %{Character.gen_character!(system, decisions) | decisions: decisions}
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "Tool Proficiencies:")
    assert String.contains?(output, "Tinker's Tools")
  end

  test "print/2 formats positive modifiers with leading +", %{
    system: system,
    character: character
  } do
    # Force a character with a known positive modifier (score 12 → mod +1)
    dex_key = {"ability", "dexterity", "base_score"}
    character = %{character | generated_values: Map.put(character.generated_values, dex_key, 12)}

    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert output =~ ~r/modifier: \+\d+/
  end

  test "print/2 formats negative modifiers without leading +", %{
    system: system,
    character: character
  } do
    # Force a score of 8 → modifier -1 for all attributes
    generated_values =
      Map.new(character.generated_values, fn {key, _} -> {key, 8} end)

    character = %{character | generated_values: generated_values}

    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert output =~ ~r/modifier: -\d+/
  end

  test "print/2 applies active effects to total_score", %{
    system: system,
    character: character
  } do
    dex_base = character.generated_values[{"ability", "dexterity", "base_score"}]
    expected_total = dex_base + 2

    character = %{
      character
      | effects: [
          %{target: {"ability", "dexterity", "total_score"}, value: 2}
        ]
    }

    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "total_score: #{expected_total}")
  end

  test "print/2 applies character effects to displayed values", %{
    system: system,
    character: character
  } do
    str_base = character.generated_values[{"ability", "strength", "base_score"}]
    expected_total = str_base + 4

    character_with_effect = %{
      character
      | effects: [
          %{
            target: {"ability", "strength", "total_score"},
            value: 4
          }
        ]
    }

    output = capture_io(fn -> CharacterDisplay.print(system, character_with_effect) end)
    assert String.contains?(output, "total_score: #{expected_total}")
  end
end
