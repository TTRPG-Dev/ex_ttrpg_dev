defmodule ExTTRPGDevTest.Characters.Store do
  # Not async: these tests override the `:characters_path` application env,
  # which is global BEAM state. Elixir's own docs warn that such overrides
  # aren't async-safe — a concurrently running async test (e.g. globals_test.exs,
  # which asserts on the *default* path) could observe the override mid-test.
  # Non-async tests are guaranteed by ExUnit to run only after all async tests
  # finish, so this avoids that race while still giving each test its own
  # isolated temp directory instead of sharing the real on-disk characters dir.
  use ExUnit.Case
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystems

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ex_ttrpg_dev_characters_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:ex_ttrpg_dev, :characters_path, tmp_dir)

    on_exit(fn ->
      Application.delete_env(:ex_ttrpg_dev, :characters_path)
      File.rm_rf(tmp_dir)
    end)

    :ok
  end

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
    File.rm(Characters.character_file_path(character))
  end

  test "character_file_path!/1 is a deprecated delegate to character_file_path/1" do
    character = build_test_character()
    assert Characters.character_file_path!(character) == Characters.character_file_path(character)
  end

  test "character_exists?/1" do
    character = build_test_character()
    assert not Characters.character_exists?(character)
    assert not Characters.character_exists?(character.metadata.slug)

    Characters.save_character!(character)
    assert Characters.character_exists?(character)
    assert Characters.character_exists?(character.metadata.slug)

    # cleanup
    delete_test_character(character)
  end

  test "save_character/1 returns :ok, and {:error, :already_exists} on collision" do
    character = build_test_character()
    assert not Characters.character_exists?(character)

    assert :ok = Characters.save_character(character)
    assert Characters.character_exists?(character)

    assert {:error, :already_exists} = Characters.save_character(character)

    assert :ok = Characters.save_character(character, true)

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

  test "list_characters!/0" do
    characters_list_first = Characters.list_characters!()
    character = save_test_character()
    characters_list_second = Characters.list_characters!()
    assert Enum.count(characters_list_first) < Enum.count(characters_list_second)
    assert Enum.member?(characters_list_second, character.metadata.slug)

    # cleanup
    delete_test_character(character)
  end

  test "list_characters/0 returns {:ok, slugs}" do
    assert {:ok, characters_list_first} = Characters.list_characters()
    character = save_test_character()
    assert {:ok, characters_list_second} = Characters.list_characters()
    assert Enum.count(characters_list_first) < Enum.count(characters_list_second)
    assert Enum.member?(characters_list_second, character.metadata.slug)

    # cleanup
    delete_test_character(character)
  end

  test "load_character/1" do
    character = save_test_character()
    loaded_character = Characters.load_character!(character.metadata.slug)
    assert character == loaded_character

    delete_test_character(character)
  end

  test "load_character/1 returns {:ok, character}, and {:error, :not_found} for unknown slug" do
    character = save_test_character()
    assert {:ok, loaded_character} = Characters.load_character(character.metadata.slug)
    assert character == loaded_character

    delete_test_character(character)

    assert {:error, :not_found} = Characters.load_character("nonexistent_character_xyz")
  end

  test "load_character/1 returns {:error, {:invalid_character_data, _}} for a corrupt file" do
    slug = "corrupt_character_xyz"
    path = Characters.character_file_path(slug)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, "not valid json")

    assert {:error, {:invalid_character_data, _message}} = Characters.load_character(slug)

    File.rm!(path)
  end

  test "delete_character/1 deletes an existing character and returns :ok" do
    character = save_test_character()
    assert Characters.character_exists?(character)

    assert :ok = Characters.delete_character(character.metadata.slug)
    refute Characters.character_exists?(character)
  end

  test "delete_character/1 returns error for unknown slug" do
    assert {:error, :not_found} = Characters.delete_character("nonexistent_character_xyz")
  end
end
