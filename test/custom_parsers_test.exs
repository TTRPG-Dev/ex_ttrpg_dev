defmodule ExTTRPGDevTest.CLI.CustomParsers do
  use ExUnit.Case

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.CLI.CustomParsers
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  doctest ExTTRPGDev.CLI.CustomParsers,
    except: [
      character_parser: 1
    ]

  def build_test_character do
    RuleSystems.list_systems()
    |> List.first()
    |> RuleSystems.load_system!()
    |> Character.gen_character!()
  end

  def save_test_character do
    character = build_test_character()
    Characters.save_character!(character)
    character
  end

  def delete_test_character(%Character{} = character) do
    File.rm(Characters.character_file_path!(character))
  end

  test "system_parser/1 returns ok with LoadedSystem for valid system" do
    assert {:ok, %LoadedSystem{}} = CustomParsers.system_parser("dnd_5e_srd")
  end

  test "system_parser/1 returns error for unknown system" do
    assert {:error, _message} = CustomParsers.system_parser("unknown_system_xyz")
  end

  test "character_parser/1 returns ok with Character for existing character" do
    character = save_test_character()

    assert {:ok, %Character{}} = CustomParsers.character_parser(character.metadata.slug)

    delete_test_character(character)
  end

  test "character_parser/1 returns error for non-existent character" do
    assert {:error, _message} = CustomParsers.character_parser("nonexistent_character_xyz")
  end
end
