defmodule ExTTRPGDev.RuleSystems.StoreBackedTest do
  # Not async: points the global store root at a fresh directory per test,
  # so installed fixtures can't leak into tests loading the real systems.
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias ExTTRPGDev.Characters.{Character, Metadata}
  alias ExTTRPGDev.RuleSystem.Store.{Entry, FileSystem}
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.{Bundled, LoadedSystem}

  @slug "dnd_5e_srd"

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_ttrpg_rs_#{System.unique_integer([:positive])}")
    previous = Application.fetch_env!(:ex_ttrpg_dev, :local_system_configs_path)

    Application.put_env(
      :ex_ttrpg_dev,
      :local_system_configs_path,
      Path.join(dir, "local_system_configs")
    )

    on_exit(fn ->
      Application.put_env(:ex_ttrpg_dev, :local_system_configs_path, previous)
      File.rm_rf!(dir)
    end)

    {:ok, bundled} = Bundled.fetch(@slug)
    {:ok, bundled: bundled}
  end

  defp install(source, is_modifiable) do
    :ok = FileSystem.put(Entry.from_source(source, is_modifiable), source, false)
  end

  defp local_copy(source, slug, version) do
    source
    |> put_in([Access.key(:module), "module", "slug"], slug)
    |> put_in([Access.key(:module), "module", "version"], version)
    |> update_in([Access.key(:module), "module"], &Map.delete(&1, "library_requirement"))
  end

  test "loading an uninstalled bundled system installs it, non-modifiable" do
    capture_log(fn -> assert {:ok, %LoadedSystem{}} = RuleSystems.load_system(@slug) end)
    assert {:ok, [%Entry{slug: @slug, is_modifiable: false}]} = FileSystem.list_entries()
  end

  test "a local system holding a bundled slug is the one loaded", ctx do
    install(local_copy(ctx.bundled, @slug, "homebrew"), true)

    assert {:ok, %LoadedSystem{module: %{version: "homebrew", library_requirement: nil}}} =
             RuleSystems.load_system(@slug)

    assert RuleSystems.local_system?(@slug)
    assert {:ok, [%Entry{version: "homebrew"}]} = FileSystem.list_entries()
  end

  test "loads the newest installed canonical version", %{bundled: bundled} do
    install(put_in(bundled.module["module"]["version"], "1.0.0"), false)
    install(put_in(bundled.module["module"]["version"], "2.0.0"), false)

    assert {:ok, %LoadedSystem{module: %{version: "2.0.0"}}} = RuleSystems.load_system(@slug)
  end

  describe "load_system/2 with a version" do
    setup %{bundled: bundled} do
      for v <- ["1.0.0", "1.2.0", "2.0.0"] do
        install(put_in(bundled.module["module"]["version"], v), false)
      end

      :ok
    end

    test "loads the newest version on the requested release line" do
      assert {:ok, %LoadedSystem{module: %{version: "1.2.0"}}} =
               RuleSystems.load_system(@slug, "1.0.0")

      assert {:ok, %LoadedSystem{module: %{version: "2.0.0"}}} =
               RuleSystems.load_system(@slug, "2.0.0")
    end

    test "fails when nothing on the release line is installed" do
      assert {:error, {:version_not_installed, @slug, "3.0.0"}} =
               RuleSystems.load_system(@slug, "3.0.0")
    end

    test "load_system_for/1 uses the character's recorded version" do
      character = %Character{
        metadata: %Metadata{rule_system: @slug, rule_system_version: "1.1.0"}
      }

      assert {:ok, %LoadedSystem{module: %{version: "1.2.0"}}} =
               RuleSystems.load_system_for(character)

      legacy = put_in(character.metadata.rule_system_version, nil)

      assert {:ok, %LoadedSystem{module: %{version: "2.0.0"}}} =
               RuleSystems.load_system_for(legacy)
    end
  end

  test "a local system loads whatever version is requested", ctx do
    install(local_copy(ctx.bundled, "my_variant", "draft 2"), true)

    assert {:ok, %LoadedSystem{module: %{version: "draft 2"}}} =
             RuleSystems.load_system("my_variant", "draft 1")
  end

  test "lists installed local systems alongside bundled ones", ctx do
    install(local_copy(ctx.bundled, "my_variant", "draft"), true)

    assert RuleSystems.list_systems() == [@slug, "my_variant"]
    assert RuleSystems.list_local_systems!() == ["my_variant"]

    assert {:ok, %LoadedSystem{module: %{slug: "my_variant"}}} =
             RuleSystems.load_system("my_variant")
  end

  test "an unknown slug is an error, and installs nothing" do
    assert {:error, {:not_configured, "nope"}} = RuleSystems.load_system("nope")
    assert {:ok, []} = FileSystem.list_entries()
  end

  describe "clone_system/3" do
    test "copies a non-modifiable system into a modifiable, non-canonical one", ctx do
      capture_log(fn ->
        assert {:ok, "my_dnd"} = RuleSystems.clone_system(@slug, "my_dnd")
      end)

      assert {:ok, clone} = FileSystem.fetch("my_dnd", ctx.bundled.module["module"]["version"])
      assert clone.concepts == ctx.bundled.concepts
      assert clone.inventory_rules == ctx.bundled.inventory_rules
      assert clone.character_building == ctx.bundled.character_building
      refute Map.has_key?(clone.module["module"], "library_requirement")

      assert %Entry{is_modifiable: true, library_requirement: nil} =
               Enum.find(RuleSystems.list_installed_systems!(), &(&1.slug == "my_dnd"))

      assert {:ok, %LoadedSystem{module: %{slug: "my_dnd"}}} = RuleSystems.load_system("my_dnd")
      assert "my_dnd" in RuleSystems.list_local_systems!()
    end

    test "a clone is never touched by sync", ctx do
      capture_log(fn ->
        {:ok, _} = RuleSystems.clone_system(@slug, "my_dnd")
        {:ok, results} = RuleSystems.sync_bundled()
        refute List.keymember?(results, "my_dnd", 0)
      end)

      assert {:ok, _} = FileSystem.fetch("my_dnd", ctx.bundled.module["module"]["version"])
    end

    test "refuses a slug that is installed or bundled", ctx do
      install(local_copy(ctx.bundled, "taken", "draft"), true)

      assert {:error, {:slug_taken, "taken"}} = RuleSystems.clone_system(@slug, "taken")
      assert {:error, {:slug_taken, @slug}} = RuleSystems.clone_system("taken", @slug)
    end

    test "fails for an unknown source" do
      assert {:error, {:not_configured, "nope"}} = RuleSystems.clone_system("nope", "x")
    end
  end

  describe "update_system/2" do
    defp rename_ability(source, name) do
      update_in(source.concepts, fn concepts ->
        Enum.map(concepts, fn {file, map} ->
          {file, put_in_existing(map, ["ability", "strength", "name"], name)}
        end)
      end)
    end

    defp put_in_existing(map, path, value) do
      if get_in(map, path), do: put_in(map, path, value), else: map
    end

    defp strength_name(slug) do
      RuleSystems.load_system!(slug).concept_metadata[{"ability", "strength"}]["name"]
    end

    setup ctx do
      install(local_copy(ctx.bundled, "my_dnd", "1.0.0"), true)
      :ok
    end

    test "edits a modifiable system in place" do
      assert :ok = RuleSystems.update_system("my_dnd", &rename_ability(&1, "Might"))
      assert strength_name("my_dnd") == "Might"
    end

    test "refuses a non-modifiable system and leaves it untouched" do
      capture_log(fn -> RuleSystems.load_system!(@slug) end)

      assert {:error, {:not_modifiable, :clone_required}} =
               RuleSystems.update_system(@slug, &rename_ability(&1, "Might"))

      assert strength_name(@slug) == "Strength"
    end

    test "can change the version" do
      assert :ok =
               RuleSystems.update_system(
                 "my_dnd",
                 &put_in(&1.module["module"]["version"], "1.1.0")
               )

      assert [%Entry{version: "1.1.0"}] =
               Enum.filter(RuleSystems.list_installed_systems!(), &(&1.slug == "my_dnd"))
    end

    test "rejects identity changes and content that doesn't load" do
      assert {:error, {:invalid_update, :slug_changed}} =
               RuleSystems.update_system("my_dnd", &put_in(&1.module["module"]["slug"], "x"))

      assert {:error, {:invalid_update, :library_requirement_changed}} =
               RuleSystems.update_system(
                 "my_dnd",
                 &put_in(&1.module["module"]["library_requirement"], "~> 0.15.0")
               )

      assert {:error, {:invalid_update, {:module_parse_error, _}}} =
               RuleSystems.update_system(
                 "my_dnd",
                 &update_in(&1.module["module"], fn m -> Map.delete(m, "name") end)
               )

      assert strength_name("my_dnd") == "Strength"
    end
  end
end
