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
end
