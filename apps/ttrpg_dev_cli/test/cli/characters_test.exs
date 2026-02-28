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

  describe "characters gen --stat-block-only" do
    setup %{optimus: optimus, halt_fn: halt_fn} do
      before_slugs = MapSet.new(Characters.list_characters!())

      output =
        capture_io(fn ->
          CLI.dispatch(["characters", "gen", "dnd_5e_srd", "--stat-block-only"], optimus, halt_fn)
        end)

      after_slugs = MapSet.new(Characters.list_characters!())
      {:ok, output: output, before_slugs: before_slugs, after_slugs: after_slugs}
    end

    test "prints the character sheet", %{output: output} do
      assert output =~ "Attributes:"
    end

    test "does not prompt to save", %{output: output} do
      refute output =~ "Would you like to save"
    end

    test "does not save a character", %{before_slugs: before_slugs, after_slugs: after_slugs} do
      assert MapSet.equal?(before_slugs, after_slugs)
    end
  end

  describe "characters gen --save" do
    setup %{optimus: optimus, halt_fn: halt_fn} do
      before_slugs = MapSet.new(Characters.list_characters!())

      output =
        capture_io(fn ->
          CLI.dispatch(["characters", "gen", "dnd_5e_srd", "--save"], optimus, halt_fn)
        end)

      after_slugs = MapSet.new(Characters.list_characters!())
      [new_slug] = MapSet.to_list(MapSet.difference(after_slugs, before_slugs))
      character = Characters.load_character!(new_slug)
      on_exit(fn -> File.rm!(Characters.character_file_path!(character)) end)

      {:ok,
       output: output,
       new_character_count: MapSet.size(MapSet.difference(after_slugs, before_slugs))}
    end

    test "prints the character sheet", %{output: output} do
      assert output =~ "Attributes:"
    end

    test "persists exactly one new character to disk", %{new_character_count: count} do
      assert count == 1
    end
  end

  describe "characters list" do
    setup do
      character = save_test_character()
      on_exit(fn -> delete_test_character(character) end)
      {:ok, character: character}
    end

    test "--system filters to only characters belonging to that system", %{
      optimus: optimus,
      halt_fn: halt_fn,
      character: character
    } do
      output =
        capture_io(fn ->
          CLI.dispatch(["characters", "list", "--system", "dnd_5e_srd"], optimus, halt_fn)
        end)

      assert output =~ character.metadata.slug
    end

    test "shows a saved character's slug, name, and system", %{
      optimus: optimus,
      halt_fn: halt_fn,
      character: character
    } do
      output = capture_io(fn -> CLI.dispatch(["characters", "list"], optimus, halt_fn) end)
      assert output =~ character.metadata.slug
      assert output =~ character.name
      assert output =~ "dnd_5e_srd"
    end

    test "output entry format is '- slug: Name [system]'", %{
      optimus: optimus,
      halt_fn: halt_fn,
      character: character
    } do
      output = capture_io(fn -> CLI.dispatch(["characters", "list"], optimus, halt_fn) end)

      assert output =~
               "- #{character.metadata.slug}: #{character.name} [#{character.metadata.rule_system}]"
    end
  end

  describe "characters show" do
    setup %{optimus: optimus, halt_fn: halt_fn} do
      character = save_test_character()
      on_exit(fn -> delete_test_character(character) end)

      output =
        capture_io(fn ->
          CLI.dispatch(["characters", "show", character.metadata.slug], optimus, halt_fn)
        end)

      {:ok, character: character, output: output}
    end

    test "prints the character sheet for a saved character", %{
      output: output,
      character: character
    } do
      assert output =~ character.name
      assert output =~ "Attributes:"
    end

    test "shows all six D&D attributes for a saved character", %{output: output} do
      for name <- ~w(Strength Dexterity Constitution Wisdom Intelligence Charisma) do
        assert output =~ name, "Expected #{name} in output"
      end
    end
  end
end
