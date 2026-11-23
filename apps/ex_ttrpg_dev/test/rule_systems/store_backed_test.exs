defmodule ExTTRPGDev.RuleSystems.StoreBackedTest do
  # Not async: points the global store root at a fresh directory per test,
  # so installed fixtures can't leak into tests loading the real systems.
  use ExUnit.Case
  import ExUnit.CaptureLog
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
end
