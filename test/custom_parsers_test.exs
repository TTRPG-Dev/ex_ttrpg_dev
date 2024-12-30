defmodule ExTTRPGDevTest.CLI.CustomParsers do
  use ExUnit.Case

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.CLI.CustomParsers
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.RuleSystem

  doctest ExTTRPGDev.CLI.CustomParsers,
    except: [
      system_parser: 1
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

  def system_parser_test do
    # If no error was raised, then all is good
    {:ok, %RuleSystem{}} = CustomParsers.system_parser("dnd_5e_srd")

    # Should raise an error
    assert_raise RuntimeError, CustomParsers.system_parser("unknown_system")
  end

  def character_parser_test do
    character = save_test_character()

    {:ok, %Character{}} = CustomParsers.character_parser(character.metadata.slug)

    # cleanup
    delete_test_character(character)

    # should raise an error
    assert_raise RuntimeError, CustomParsers.character_parser(character.metadata.slug)

    assert False
  end
end
