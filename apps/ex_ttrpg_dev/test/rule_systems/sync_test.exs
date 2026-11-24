defmodule ExTTRPGDev.RuleSystems.SyncTest do
  # Not async: points the global store and characters roots at a fresh
  # directory per test, so fake installed versions can't leak into tests
  # that load the real bundled systems.
  use ExUnit.Case
  import ExUnit.CaptureLog
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, Metadata}
  alias ExTTRPGDev.RuleSystem.Source
  alias ExTTRPGDev.RuleSystem.Store.{Entry, FileSystem}
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.{Bundled, Sync}

  @slug "dnd_5e_srd"

  setup do
    dir = Path.join(System.tmp_dir!(), "ex_ttrpg_sync_#{System.unique_integer([:positive])}")
    systems = Path.join(dir, "local_system_configs")
    previous = Application.fetch_env!(:ex_ttrpg_dev, :local_system_configs_path)
    Application.put_env(:ex_ttrpg_dev, :local_system_configs_path, systems)
    Application.put_env(:ex_ttrpg_dev, :characters_path, Path.join(dir, "local_characters"))

    on_exit(fn ->
      Application.put_env(:ex_ttrpg_dev, :local_system_configs_path, previous)
      Application.delete_env(:ex_ttrpg_dev, :characters_path)
      File.rm_rf!(dir)
    end)

    {:ok, bundled} = Bundled.fetch(@slug)
    {:ok, systems: systems, bundled: bundled, version: bundled.module["module"]["version"]}
  end

  defp with_version(%Source{} = source, version) do
    put_in(source.module["module"]["version"], version)
  end

  defp install(source, is_modifiable \\ false) do
    :ok = FileSystem.put(Entry.from_source(source, is_modifiable), source, false)
  end

  defp sync_dnd do
    {result, _log} =
      with_log(fn ->
        {:ok, results} = RuleSystems.sync_bundled()
        Map.new(results)
      end)

    result[@slug]
  end

  test "seeds a bundled system into an empty store as non-modifiable", ctx do
    assert {:apply, %{install: version, remove: []}} = sync_dnd()
    assert version == ctx.version

    assert {:ok, [%Entry{slug: @slug, version: ^version, is_modifiable: false}]} =
             FileSystem.list_entries()
  end

  test "logs every decision" do
    assert capture_log(fn -> RuleSystems.sync_bundled() end) =~ ~s("#{@slug}")
  end

  test "is a no-op once installed", ctx do
    sync_dnd()
    assert {:skip, {:already_installed, v}} = sync_dnd()
    assert v == ctx.version
  end

  test "never touches a local system holding the slug", ctx do
    local = with_version(ctx.bundled, "homebrew")

    local = update_in(local.module["module"], &Map.delete(&1, "library_requirement"))

    install(local, true)

    assert {:skip, {:slug_taken, "homebrew"}} = sync_dnd()
    assert {:ok, [%Entry{version: "homebrew", is_modifiable: true}]} = FileSystem.list_entries()
  end

  test "replaces an older breaking version nothing depends on", ctx do
    install(with_version(ctx.bundled, "0.9.0"))

    assert {:apply, %{remove: ["0.9.0"], retain: []}} = sync_dnd()
    assert {:ok, [%Entry{version: v}]} = FileSystem.list_entries()
    assert v == ctx.version
  end

  test "keeps an older breaking version that characters depend on", ctx do
    install(with_version(ctx.bundled, "0.9.0"))

    :ok =
      Characters.save_character(%Character{
        name: "Old Hero",
        generated_values: %{},
        metadata: %Metadata{slug: "old_hero", rule_system: @slug, rule_system_version: "0.9.0"}
      })

    assert {:apply, %{remove: [], retain: [{"0.9.0", [_]}]}} = sync_dnd()
    assert {:ok, entries} = FileSystem.list_entries()
    assert Enum.map(entries, & &1.version) |> Enum.sort() == Enum.sort(["0.9.0", ctx.version])
  end

  describe "seed_if_absent/1" do
    test "installs an absent bundled system" do
      capture_log(fn -> assert :ok = Sync.seed_if_absent(@slug) end)
      assert {:ok, [%Entry{slug: @slug}]} = FileSystem.list_entries()
    end

    test "leaves an installed slug alone, even an older version", ctx do
      install(with_version(ctx.bundled, "0.9.0"))
      assert :ok = Sync.seed_if_absent(@slug)
      assert {:ok, [%Entry{version: "0.9.0"}]} = FileSystem.list_entries()
    end

    test "ignores slugs that aren't bundled" do
      assert :ok = Sync.seed_if_absent("not_bundled")
      assert {:ok, []} = FileSystem.list_entries()
    end
  end
end
