defmodule ExTTRPGDev.RuleSystems.StoreBackedTest do
  # Not async: points the global store root at a fresh directory per test,
  # so installed fixtures can't leak into tests loading the real systems.
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, Metadata}
  alias ExTTRPGDev.RuleSystem.Store.{Entry, FileSystem}
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.{Bundled, Dependents, LoadedSystem}

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

  describe "create_system/1" do
    test "stores a modifiable, non-canonical system that loads" do
      assert {:ok, "my_fantasy_system"} =
               RuleSystems.create_system(%{
                 "name" => "My Fantasy System",
                 "publisher" => "Acme Games"
               })

      assert {:ok, source} = FileSystem.fetch("my_fantasy_system", "1.0.0")

      assert source.module == %{
               "module" => %{
                 "name" => "My Fantasy System",
                 "slug" => "my_fantasy_system",
                 "version" => "1.0.0",
                 "publisher" => "Acme Games"
               }
             }

      assert source.concepts == []

      assert %Entry{is_modifiable: true, library_requirement: nil} =
               Enum.find(RuleSystems.list_installed_systems!(), &(&1.slug == "my_fantasy_system"))

      assert {:ok, %LoadedSystem{module: %{name: "My Fantasy System"}}} =
               RuleSystems.load_system("my_fantasy_system")

      assert "my_fantasy_system" in RuleSystems.list_local_systems!()
    end

    test "omits blank optional fields, trims values, and keeps a given version and slug" do
      assert {:ok, "homebrew"} =
               RuleSystems.create_system(%{
                 "name" => "  Homebrew  ",
                 "slug" => "homebrew",
                 "version" => "0.1",
                 "family" => "",
                 "series" => "   ",
                 "publisher" => nil
               })

      assert {:ok, %{module: %{"module" => module}}} = FileSystem.fetch("homebrew", "0.1")
      assert module == %{"name" => "Homebrew", "slug" => "homebrew", "version" => "0.1"}
    end

    test "derives a slug from a non-ASCII name, in NFC form" do
      # e + combining acute, which must give the same slug as a composed é
      decomposed = "Cafe\u0301 Rules"
      refute decomposed == "Café Rules"
      assert {:ok, "café_rules"} = RuleSystems.create_system(%{"name" => decomposed})
      assert {:ok, %LoadedSystem{}} = RuleSystems.load_system("café_rules")
    end

    test "refuses a slug that is installed or bundled" do
      assert {:ok, "taken"} = RuleSystems.create_system(%{"name" => "Taken"})
      assert {:error, {:slug_taken, "taken"}} = RuleSystems.create_system(%{"name" => "taken"})

      assert {:error, {:slug_taken, @slug}} =
               RuleSystems.create_system(%{"name" => "x", "slug" => @slug})

      assert {:ok, [%Entry{slug: "taken"}]} = FileSystem.list_entries()
    end

    test "rejects invalid input without storing anything" do
      for {fields, error} <- [
            {%{}, {:invalid_module, {:missing_required_key, "name"}}},
            {%{"name" => " "}, {:invalid_module, {:missing_required_key, "name"}}},
            {%{"name" => "!!!"}, {:invalid_slug, ""}},
            {%{"name" => "X", "slug" => "Not A Slug"}, {:invalid_slug, "Not A Slug"}},
            {%{"name" => "X", "level_node" => "y"},
             {:invalid_module, {:unknown_key, "level_node"}}},
            {%{"name" => "X", "library_requirement" => "~> 0.1"},
             {:invalid_module, {:unknown_key, "library_requirement"}}},
            {%{"name" => 3}, {:invalid_module, {:not_a_string, "name", 3}}}
          ] do
        assert {:error, ^error} = RuleSystems.create_system(fields)
      end

      assert {:ok, []} = FileSystem.list_entries()
    end
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

  describe "delete_system/1" do
    defmodule HostDependents do
      @behaviour ExTTRPGDev.RuleSystems.Dependents
      @impl true
      def dependents("my_dnd", "1.0.0"), do: {:ok, [{:campaign, 7}]}
      def dependents(_, _), do: {:ok, []}
    end

    defmodule FailingDependents do
      @behaviour ExTTRPGDev.RuleSystems.Dependents
      @impl true
      def dependents(_, _), do: {:error, :db_down}
    end

    setup ctx do
      characters =
        Path.join(System.tmp_dir!(), "ex_ttrpg_rs_chars_#{System.unique_integer([:positive])}")

      Application.put_env(:ex_ttrpg_dev, :characters_path, characters)

      on_exit(fn ->
        Application.delete_env(:ex_ttrpg_dev, :characters_path)
        Application.delete_env(:ex_ttrpg_dev, :rule_system_dependents)
        File.rm_rf!(characters)
      end)

      install(local_copy(ctx.bundled, "my_dnd", "1.0.0"), true)
      :ok
    end

    defp save_character_on(slug, rule_system, version) do
      :ok =
        Characters.save_character(%Character{
          name: slug,
          generated_values: %{},
          metadata: %Metadata{slug: slug, rule_system: rule_system, rule_system_version: version}
        })
    end

    defp installed?(slug),
      do: Enum.any?(RuleSystems.list_installed_systems!(), &(&1.slug == slug))

    test "removes a modifiable system from the store" do
      assert :ok = RuleSystems.delete_system("my_dnd")
      refute installed?("my_dnd")
      refute RuleSystems.configured?("my_dnd")
      assert {:error, {:not_configured, "my_dnd"}} = RuleSystems.load_system("my_dnd")
    end

    test "refuses a non-modifiable system and leaves it installed" do
      capture_log(fn -> RuleSystems.load_system!(@slug) end)

      assert {:error, :not_modifiable} = RuleSystems.delete_system(@slug)
      assert installed?(@slug)
    end

    test "refuses an uninstalled bundled system without installing it" do
      assert {:error, :not_modifiable} = RuleSystems.delete_system(@slug)
      refute installed?(@slug)
    end

    test "a local system holding a bundled slug can be deleted", ctx do
      install(local_copy(ctx.bundled, @slug, "homebrew"), true)

      assert :ok = RuleSystems.delete_system(@slug)
      refute installed?(@slug)
    end

    test "fails for an unknown slug" do
      assert {:error, {:not_configured, "nope"}} = RuleSystems.delete_system("nope")
    end

    test "refuses while characters use the system, at any version they recorded" do
      save_character_on("current", "my_dnd", "1.0.0")
      save_character_on("from_an_older_major", "my_dnd", "0.3.0")
      save_character_on("elsewhere", "other", "1.0.0")

      assert {:error, {:has_dependents, found}} = RuleSystems.delete_system("my_dnd")

      assert Enum.sort(found) == [
               {Dependents, "current"},
               {Dependents, "from_an_older_major"}
             ]

      assert installed?("my_dnd")
    end

    test "refuses while a host reports dependents" do
      Application.put_env(:ex_ttrpg_dev, :rule_system_dependents, [HostDependents])

      assert {:error, {:has_dependents, [{HostDependents, {:campaign, 7}}]}} =
               RuleSystems.delete_system("my_dnd")

      assert installed?("my_dnd")
    end

    test "refuses when dependents can't be determined" do
      Application.put_env(:ex_ttrpg_dev, :rule_system_dependents, [FailingDependents])

      assert {:error, {:dependents_unavailable, {FailingDependents, :db_down}}} =
               RuleSystems.delete_system("my_dnd")

      File.mkdir_p!(Application.fetch_env!(:ex_ttrpg_dev, :characters_path))
      Application.delete_env(:ex_ttrpg_dev, :rule_system_dependents)
      File.write!(Characters.character_file_path("corrupt"), "not json")

      assert {:error, {:dependents_unavailable, {Dependents, {:unreadable_characters, [_]}}}} =
               RuleSystems.delete_system("my_dnd")

      assert installed?("my_dnd")
    end
  end
end
