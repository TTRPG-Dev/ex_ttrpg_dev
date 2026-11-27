defmodule ExTTRPGDevTest.RuleSystems do
  use ExUnit.Case
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.LoadedSystem
  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.RuleSystem.Versioning

  doctest ExTTRPGDev.RuleSystems

  test "load_system!/1 for bundled system returns a LoadedSystem" do
    [bundled_system_slug | _tail] = RuleSystems.list_bundled_systems!()

    %LoadedSystem{module: rule_module} = RuleSystems.load_system!(bundled_system_slug)

    assert rule_module.slug == bundled_system_slug
  end

  # Bundled systems are canonical content: they must declare a
  # library_requirement, and the library they ship in must satisfy it. The
  # release workflow re-certifies bundled requirements on a minor/major lib
  # bump; this catches a version bumped any other way.
  test "every bundled system is canonical and compatible with the running library" do
    for slug <- RuleSystems.list_bundled_systems!() do
      %LoadedSystem{module: mod} = RuleSystems.load_system!(slug)
      assert Versioning.canonical?(mod), "#{slug} declares no library_requirement"

      assert Versioning.library_compatible?(mod),
             "#{slug} requires #{mod.library_requirement}, " <>
               "running library is #{Versioning.library_version()}"
    end
  end

  test "load_system!/1 for unconfigured system raises" do
    assert_raise RuntimeError, fn -> RuleSystems.load_system!("not_a_real_system_xyz") end
  end

  test "load_system/1 for bundled system returns {:ok, %LoadedSystem{}}" do
    [bundled_system_slug | _tail] = RuleSystems.list_bundled_systems!()

    assert {:ok, %LoadedSystem{module: rule_module}} =
             RuleSystems.load_system(bundled_system_slug)

    assert rule_module.slug == bundled_system_slug
  end

  test "load_system/1 for unconfigured system returns an error tuple" do
    assert {:error, _reason} = RuleSystems.load_system("not_a_real_system_xyz")
  end

  test "system_path/1" do
    [bundled_system_slug | _tail] = RuleSystems.list_bundled_systems!()

    assert RuleSystems.system_path(bundled_system_slug) ==
             Path.join([Globals.system_configs_path(), bundled_system_slug])

    custom_slug = "custom_system"

    assert RuleSystems.system_path(custom_slug) ==
             Path.join([Globals.local_system_configs_path(), custom_slug])
  end

  test "system_path!/1 is a deprecated delegate to system_path/1" do
    [bundled_system_slug | _tail] = RuleSystems.list_bundled_systems!()

    assert RuleSystems.system_path!(bundled_system_slug) ==
             RuleSystems.system_path(bundled_system_slug)
  end

  test "bundled_system?/1 returns true for bundled system" do
    assert RuleSystems.bundled_system?("dnd_5e_srd")
  end

  test "bundled_system?/1 returns false for unknown system" do
    refute RuleSystems.bundled_system?("unknown_system_xyz")
  end

  test "local_system?/1 returns false for bundled system" do
    assert not RuleSystems.local_system?("dnd_5e_srd")
  end

  test "is_bundled_system?/1, is_local_system?/1, is_configured?/1 are deprecated delegates" do
    assert RuleSystems.is_bundled_system?("dnd_5e_srd") ==
             RuleSystems.bundled_system?("dnd_5e_srd")

    assert RuleSystems.is_local_system?("dnd_5e_srd") == RuleSystems.local_system?("dnd_5e_srd")
    assert RuleSystems.is_configured?("dnd_5e_srd") == RuleSystems.configured?("dnd_5e_srd")
  end

  test "list_local_systems!/0 returns a list" do
    assert is_list(RuleSystems.list_local_systems!())
  end

  test "list_systems/0 includes bundled systems" do
    assert "dnd_5e_srd" in RuleSystems.list_systems()
  end

  test "list_bundled_systems!/0 includes dnd_5e_srd" do
    assert "dnd_5e_srd" in RuleSystems.list_bundled_systems!()
  end

  test "fetch_bundled_systems/0 returns {:ok, slugs} including dnd_5e_srd" do
    assert {:ok, slugs} = RuleSystems.fetch_bundled_systems()
    assert "dnd_5e_srd" in slugs
  end

  test "fetch_local_systems/0 returns {:ok, slugs}" do
    assert {:ok, slugs} = RuleSystems.fetch_local_systems()
    assert is_list(slugs)
  end

  test "fetch_systems/0 returns {:ok, slugs} including bundled and local systems" do
    assert {:ok, slugs} = RuleSystems.fetch_systems()
    assert "dnd_5e_srd" in slugs
    assert slugs == RuleSystems.list_systems()
  end

  test "list_bundled_systems/0 and list_local_systems/0 are deprecated delegates" do
    assert RuleSystems.list_bundled_systems() == RuleSystems.list_bundled_systems!()
    assert RuleSystems.list_local_systems() == RuleSystems.list_local_systems!()
  end

  test "load_system!/1 returns LoadedSystem with nodes and rolling_methods" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    assert map_size(system.nodes) == 266
    assert Map.has_key?(system.rolling_methods, "standard")
  end
end
