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

  test "print/2 shows Attributes section", %{system: system, character: character} do
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "Attributes:")
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

  test "print/2 skips concept types with no DAG nodes (languages)", %{
    system: system,
    character: character
  } do
    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    refute String.contains?(output, "Languages:")
  end

  test "print/2 formats positive modifiers with leading +", %{
    system: system,
    character: character
  } do
    # Force a character with a known positive modifier (score 12 → mod +1)
    dex_key = {"attr", "dexterity", "base_score"}
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
    dex_base = character.generated_values[{"attr", "dexterity", "base_score"}]
    expected_total = dex_base + 2

    character = %{
      character
      | effects: [
          %{target: {"attr", "dexterity", "total_score"}, value: 2}
        ]
    }

    output = capture_io(fn -> CharacterDisplay.print(system, character) end)
    assert String.contains?(output, "total_score: #{expected_total}")
  end

  test "print/2 merges system-level effects with character effects", %{
    system: system,
    character: character
  } do
    str_base = character.generated_values[{"attr", "strength", "base_score"}]
    expected_total = str_base + 4

    system_with_contrib = %{
      system
      | effects: [
          %{
            source: {"feat", "tough", nil},
            target: {"attr", "strength", "total_score"},
            value: 4
          }
        ]
    }

    output = capture_io(fn -> CharacterDisplay.print(system_with_contrib, character) end)
    assert String.contains?(output, "total_score: #{expected_total}")
  end
end
