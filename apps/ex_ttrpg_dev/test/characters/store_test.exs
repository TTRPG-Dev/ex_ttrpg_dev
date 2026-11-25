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
  alias ExTTRPGDev.Characters.{Character, Metadata}
  alias ExTTRPGDev.RuleSystems

  doctest ExTTRPGDev.Characters.Store

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

  describe "characters_depending_on/2" do
    defp save_with_version(slug, rule_system, version) do
      character = %Character{
        name: slug,
        generated_values: %{},
        metadata: %Metadata{slug: slug, rule_system: rule_system, rule_system_version: version}
      }

      :ok = Characters.save_character(character)
    end

    test "matches characters on the same release line of the system" do
      save_with_version("exact", "sys", "1.2.0")
      save_with_version("older_patch", "sys", "1.1.9")
      save_with_version("next_major", "sys", "2.0.0")
      save_with_version("other_system", "other", "1.2.0")

      assert {:ok, slugs} = Characters.characters_depending_on("sys", "1.2.0")
      assert Enum.sort(slugs) == ["exact", "older_patch"]
    end

    test "treats characters without a recorded version as depending on every version" do
      save_with_version("legacy", "sys", nil)

      assert {:ok, ["legacy"]} = Characters.characters_depending_on("sys", "9.0.0")
      assert {:ok, []} = Characters.characters_depending_on("other", "9.0.0")
    end

    test "compares non-SemVer versions by equality" do
      save_with_version("draft", "sys", "first draft")

      assert {:ok, ["draft"]} = Characters.characters_depending_on("sys", "first draft")
      assert {:ok, []} = Characters.characters_depending_on("sys", "second draft")
    end

    test "returns an empty list when no characters are saved" do
      assert {:ok, []} = Characters.characters_depending_on("sys", "1.0.0")
    end

    test "fails closed when a saved character can't be read" do
      save_with_version("fine", "sys", "1.0.0")
      File.write!(Characters.character_file_path("corrupt"), "not json")

      assert {:error, {:unreadable_characters, [{"corrupt", _reason}]}} =
               Characters.characters_depending_on("sys", "1.0.0")
    end
  end

  describe "slug validation" do
    defp named(slug) do
      %Character{
        name: slug,
        generated_values: %{},
        metadata: %Metadata{slug: slug, rule_system: "sys"}
      }
    end

    test "slugs that could escape the characters directory never touch the filesystem" do
      # A uniquely named file just outside the characters directory, which
      # "../{name}" would reach if slugs weren't validated.
      dir = Application.fetch_env!(:ex_ttrpg_dev, :characters_path)
      name = "escape_target_#{System.unique_integer([:positive])}"
      outside = Path.join(Path.dirname(dir), "#{name}.json")
      File.mkdir_p!(dir)
      File.write!(outside, "{}")
      on_exit(fn -> File.rm(outside) end)
      escaping = "../#{name}"

      assert {:error, {:invalid_slug, ^escaping}} = Characters.delete_character(escaping)
      assert {:error, {:invalid_slug, ^escaping}} = Characters.load_character(escaping)
      refute Characters.character_exists?(escaping)
      assert File.exists?(outside)

      assert {:error, {:invalid_slug, "a/b"}} = Characters.save_character(named("a/b"))
      assert_raise ArgumentError, fn -> Characters.character_file_path("../notes") end
    end

    test "bang variants raise naming the invalid slug" do
      assert_raise RuntimeError, ~r/invalid_slug/, fn -> Characters.load_character!("../x") end

      assert_raise RuntimeError, ~r/invalid_slug/, fn ->
        Characters.save_character!(named("a/b"))
      end
    end

    test "characters with slugs in any script round-trip" do
      zoe = named("zoë")
      assert :ok = Characters.save_character(zoe)
      assert Characters.character_exists?("zoë")
      assert {:ok, ^zoe} = Characters.load_character("zoë")
      assert "zoë" in Characters.list_characters!()
    end

    test "list_characters/0 ignores files that aren't {valid_slug}.json" do
      :ok = Characters.save_character(named("kept"))
      dir = Application.fetch_env!(:ex_ttrpg_dev, :characters_path)

      for stray <- [".tmp-123.json", "notes.txt", "has space.json", ".DS_Store"] do
        File.write!(Path.join(dir, stray), "{}")
      end

      assert Characters.list_characters!() == ["kept"]
    end
  end

  describe "atomic saves" do
    defp versioned(slug, n) do
      %Character{
        name: "#{slug} v#{n}",
        generated_values: %{},
        metadata: %Metadata{slug: slug, rule_system: "sys"}
      }
    end

    defp dir_entries do
      File.ls!(Application.fetch_env!(:ex_ttrpg_dev, :characters_path)) |> Enum.sort()
    end

    test "concurrent non-overwriting saves of one new slug: exactly one wins" do
      for round <- 1..10 do
        slug = "race_#{round}"

        results =
          1..8
          |> Enum.map(fn n ->
            Task.async(fn -> Characters.save_character(versioned(slug, n)) end)
          end)
          |> Task.await_many()

        assert Enum.count(results, &(&1 == :ok)) == 1
        assert Enum.count(results, &(&1 == {:error, :already_exists})) == 7
        assert {:ok, %Character{}} = Characters.load_character(slug)
      end
    end

    test "concurrent overwriting saves leave one complete character" do
      results =
        1..8
        |> Enum.map(fn n ->
          Task.async(fn -> Characters.save_character(versioned("hot", n), true) end)
        end)
        |> Task.await_many()

      assert Enum.all?(results, &(&1 == :ok))
      assert {:ok, %Character{name: "hot v" <> _}} = Characters.load_character("hot")
    end

    test "saves leave no temporary files behind, including refused ones" do
      :ok = Characters.save_character(versioned("tidy", 1))
      :ok = Characters.save_character(versioned("tidy", 2), true)
      {:error, :already_exists} = Characters.save_character(versioned("tidy", 3))

      assert dir_entries() == ["tidy.json"]
    end

    test "a failed save leaves the existing character unchanged" do
      :ok = Characters.save_character(versioned("keep", 1))
      dir = Application.fetch_env!(:ex_ttrpg_dev, :characters_path)
      File.chmod!(dir, 0o555)
      on_exit(fn -> File.chmod(dir, 0o755) end)

      # Running as root ignores directory permissions; nothing to check then.
      probe = Path.join(dir, ".probe")

      if File.write(probe, "") == :ok do
        File.rm(probe)
      else
        assert {:error, _} = Characters.save_character(versioned("keep", 2), true)
        assert Characters.load_character!("keep").name == "keep v1"
        assert dir_entries() == ["keep.json"]
      end
    end
  end
end
