defmodule ExTTRPGDevTest.Globals do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Globals

  doctest ExTTRPGDev.Globals

  test "system_configs_path/0 returns a string path ending in priv/system_configs" do
    path = Globals.system_configs_path()
    assert is_binary(path)
    assert String.ends_with?(path, "priv/system_configs")
  end

  test "local_system_configs_path/0 returns a string path ending in local_system_configs" do
    path = Globals.local_system_configs_path()
    assert is_binary(path)
    assert String.ends_with?(path, "local_system_configs")
  end

  test "characters_path/0 returns a string path ending in local_characters" do
    path = Globals.characters_path()
    assert is_binary(path)
    assert String.ends_with?(path, "local_characters")
  end

  test "local_system_configs_path/0 returns the configured path when set" do
    Application.put_env(:ex_ttrpg_dev, :local_system_configs_path, "/tmp/injected_systems")
    on_exit(fn -> Application.delete_env(:ex_ttrpg_dev, :local_system_configs_path) end)

    assert Globals.local_system_configs_path() == "/tmp/injected_systems"
  end

  test "characters_path/0 returns the configured path when set" do
    Application.put_env(:ex_ttrpg_dev, :characters_path, "/tmp/injected_characters")
    on_exit(fn -> Application.delete_env(:ex_ttrpg_dev, :characters_path) end)

    assert Globals.characters_path() == "/tmp/injected_characters"
  end
end
