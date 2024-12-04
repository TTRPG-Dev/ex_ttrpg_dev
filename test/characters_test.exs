defmodule ExTTRPGDevTest.Characters do
  use ExUnit.Case
  alias ExTTRPGDev.RuleSystems.Characters
  alias ExTTRPGDev.RuleSystems.RuleSystem
  alias ExTTRPGDev.RuleSystems

  doctest ExTTRPGDev.RuleSystems.Characters,
    except: [
      character_file_path!: 1,
      character_exists?: 1,
      save_character!: 1,
      save_character!: 2
    ]

  def build_test_character do
    RuleSystems.list_systems()
    |> List.first()
    |> RuleSystems.load_system!()
    |> RuleSystem.gen_character!()
  end

  def save_test_character do
    character = build_test_character()
    Characters.save_character!(character)
    character
  end

  def delete_test_character(%Characters.Character{} = character) do
    File.rm(Characters.character_file_path!(character))
  end

  test "character_exists?/1" do
    character = build_test_character()
    assert not Characters.character_exists?(character)

    Characters.save_character!(character)
    assert Characters.character_exists?(character)

    # cleanup
    delete_test_character(character)
  end

  test "save_character!/1" do
    character = build_test_character()
    assert not Characters.character_exists?(character)

    Characters.save_character!(character)
    assert Characters.character_exists?(character)

    assert_raise RuntimeError, fn -> Characters.save_character!(character) end

    # cleanup
    delete_test_character(character)
  end

  test "save_character!/2" do
    character = build_test_character()
    assert not Characters.character_exists?(character)

    Characters.save_character!(character)
    assert Characters.character_exists?(character)

    Characters.save_character!(character, true)
    assert Characters.character_exists?(character)

    # cleanup
    delete_test_character(character)
  end
end
