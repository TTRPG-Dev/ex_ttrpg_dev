defmodule ExTTRPGDevTest.RuleSystems do
  use ExUnit.Case
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.LoadedSystem
  alias ExTTRPGDev.Globals

  doctest ExTTRPGDev.RuleSystems

  test "load_system!/1 for bundled system returns a LoadedSystem" do
    [bundled_system_slug | _tail] = RuleSystems.list_bundled_systems()

    %LoadedSystem{module: rule_module} = RuleSystems.load_system!(bundled_system_slug)

    assert rule_module.slug == bundled_system_slug
  end

  test "load_system!/1 for unconfigured system raises" do
    assert_raise RuntimeError, fn -> RuleSystems.load_system!("not_a_real_system_xyz") end
  end

  test "system_path!/1" do
    [bundled_system_slug | _tail] = RuleSystems.list_bundled_systems()

    assert RuleSystems.system_path!(bundled_system_slug) ==
             Path.join([Globals.system_configs_path(), bundled_system_slug])

    custom_slug = "custom_system"

    assert RuleSystems.system_path!(custom_slug) ==
             Path.join([Globals.local_system_configs_path(), custom_slug])
  end

  test "is_bundled_system?/1 returns true for bundled system" do
    assert RuleSystems.is_bundled_system?("dnd_5e_srd")
  end

  test "is_bundled_system?/1 returns false for unknown system" do
    refute RuleSystems.is_bundled_system?("unknown_system_xyz")
  end

  test "is_local_system?/1 returns false for bundled system" do
    assert not RuleSystems.is_local_system?("dnd_5e_srd")
  end

  test "list_local_systems/0 returns a list" do
    assert is_list(RuleSystems.list_local_systems())
  end

  test "list_systems/0 includes bundled systems" do
    assert "dnd_5e_srd" in RuleSystems.list_systems()
  end

  test "list_bundled_systems/0 includes dnd_5e_srd" do
    assert "dnd_5e_srd" in RuleSystems.list_bundled_systems()
  end

  test "load_system!/1 returns LoadedSystem with nodes and rolling_methods" do
    system = RuleSystems.load_system!("dnd_5e_srd")
    assert map_size(system.nodes) == 36
    assert Map.has_key?(system.rolling_methods, "standard")
  end
end
