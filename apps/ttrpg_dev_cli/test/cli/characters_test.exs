defmodule ExTTRPGDevTest.CLI.Characters do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.CLI
  alias ExTTRPGDev.RuleSystems

  setup do
    optimus = CLI.build_optimus()
    halt_fn = fn _code -> nil end
    {:ok, optimus: optimus, halt_fn: halt_fn}
  end

  defp save_test_character do
    system = RuleSystems.load_system!("dnd_5e_srd")
    character = Character.gen_character!(system)
    Characters.save_character!(character)
    character
  end

  defp delete_test_character(%Character{} = character) do
    File.rm!(Characters.character_file_path!(character))
  end

  describe "characters gen" do
    test "--stat-block-only prints the character sheet", %{optimus: optimus, halt_fn: halt_fn} do
      output =
        capture_io(fn ->
          CLI.dispatch(["characters", "gen", "dnd_5e_srd", "--stat-block-only"], optimus, halt_fn)
        end)

      assert output =~ "Attributes:"
    end

    test "--stat-block-only does not prompt to save", %{optimus: optimus, halt_fn: halt_fn} do
      output =
        capture_io(fn ->
          CLI.dispatch(["characters", "gen", "dnd_5e_srd", "--stat-block-only"], optimus, halt_fn)
        end)

      refute output =~ "Would you like to save"
    end

    test "--stat-block-only does not save a character", %{optimus: optimus, halt_fn: halt_fn} do
      before_slugs = MapSet.new(Characters.list_characters!())

      capture_io(fn ->
        CLI.dispatch(["characters", "gen", "dnd_5e_srd", "--stat-block-only"], optimus, halt_fn)
      end)

      after_slugs = MapSet.new(Characters.list_characters!())
      assert MapSet.equal?(before_slugs, after_slugs)
    end

    test "--save prints the character sheet", %{optimus: optimus, halt_fn: halt_fn} do
      before_slugs = MapSet.new(Characters.list_characters!())

      output =
        capture_io(fn ->
          CLI.dispatch(["characters", "gen", "dnd_5e_srd", "--save"], optimus, halt_fn)
        end)

      assert output =~ "Attributes:"

      # Cleanup
      after_slugs = MapSet.new(Characters.list_characters!())
      [new_slug] = MapSet.to_list(MapSet.difference(after_slugs, before_slugs))
      delete_test_character(Characters.load_character!(new_slug))
    end

    test "--save persists the character to disk", %{optimus: optimus, halt_fn: halt_fn} do
      before_slugs = MapSet.new(Characters.list_characters!())

      capture_io(fn ->
        CLI.dispatch(["characters", "gen", "dnd_5e_srd", "--save"], optimus, halt_fn)
      end)

      after_slugs = MapSet.new(Characters.list_characters!())
      new_slugs = MapSet.difference(after_slugs, before_slugs)
      assert MapSet.size(new_slugs) == 1

      # Cleanup
      [new_slug] = MapSet.to_list(new_slugs)
      delete_test_character(Characters.load_character!(new_slug))
    end
  end

  describe "characters list" do
    test "--system filters to only characters belonging to that system", %{
      optimus: optimus,
      halt_fn: halt_fn
    } do
      character = save_test_character()

      output =
        capture_io(fn ->
          CLI.dispatch(["characters", "list", "--system", "dnd_5e_srd"], optimus, halt_fn)
        end)

      assert output =~ character.metadata.slug

      delete_test_character(character)
    end

    test "shows a saved character's slug, name, and system", %{
      optimus: optimus,
      halt_fn: halt_fn
    } do
      character = save_test_character()

      output =
        capture_io(fn -> CLI.dispatch(["characters", "list"], optimus, halt_fn) end)

      assert output =~ character.metadata.slug
      assert output =~ character.name
      assert output =~ "dnd_5e_srd"

      delete_test_character(character)
    end

    test "output entry format is '- slug: Name [system]'", %{
      optimus: optimus,
      halt_fn: halt_fn
    } do
      character = save_test_character()

      output =
        capture_io(fn -> CLI.dispatch(["characters", "list"], optimus, halt_fn) end)

      assert output =~
               "- #{character.metadata.slug}: #{character.name} [#{character.metadata.rule_system}]"

      delete_test_character(character)
    end
  end

  describe "characters show" do
    test "prints the character sheet for a saved character", %{
      optimus: optimus,
      halt_fn: halt_fn
    } do
      character = save_test_character()

      output =
        capture_io(fn ->
          CLI.dispatch(["characters", "show", character.metadata.slug], optimus, halt_fn)
        end)

      assert output =~ character.name
      assert output =~ "Attributes:"

      delete_test_character(character)
    end

    test "shows all six D&D attributes for a saved character", %{
      optimus: optimus,
      halt_fn: halt_fn
    } do
      character = save_test_character()

      output =
        capture_io(fn ->
          CLI.dispatch(["characters", "show", character.metadata.slug], optimus, halt_fn)
        end)

      for name <- ~w(Strength Dexterity Constitution Wisdom Intelligence Charisma) do
        assert output =~ name, "Expected #{name} in output"
      end

      delete_test_character(character)
    end
  end
end
