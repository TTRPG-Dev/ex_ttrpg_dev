defmodule ExTTRPGDev.RuleSystem.SourceTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.{Loader, Source}

  @dnd_path Application.app_dir(:ex_ttrpg_dev, "priv/system_configs/dnd_5e_srd")

  defp tmp_dir do
    dir = Path.join(System.tmp_dir!(), "ex_ttrpg_source_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)
    dir
  end

  test "read/1 decodes every file of a system" do
    assert {:ok, %Source{} = source} = Source.read(@dnd_path)
    assert source.module["module"]["slug"] == "dnd_5e_srd"
    assert is_map(source.character_building)
    assert is_map(source.inventory_rules)
    assert [{"concepts/" <> _, %{}} | _] = source.concepts
    assert source.concepts == Enum.sort_by(source.concepts, &elem(&1, 0))
  end

  test "read/1 treats missing optional files as nil" do
    dir = tmp_dir()
    File.write!(Path.join(dir, "module.toml"), ~s([module]\nname = "X"\nslug = "x"\n))

    assert {:ok, %Source{character_building: nil, inventory_rules: nil, concepts: []}} =
             Source.read(dir)
  end

  test "read/1 names the concept file that failed to decode" do
    dir = tmp_dir()
    File.write!(Path.join(dir, "module.toml"), ~s([module]\nname = "X"\n))
    File.mkdir_p!(Path.join(dir, "concepts"))
    bad = Path.join(dir, "concepts/bad.toml")
    File.write!(bad, "not = = toml")

    assert {:error, {:file_parse_error, ^bad, _}} = Source.read(dir)
  end

  test "read/1 reports a missing module.toml" do
    assert {:error, {:module_parse_error, :enoent}} = Source.read(tmp_dir())
  end

  test "write/2 produces a directory read/1 decodes back to the same source" do
    {:ok, source} = Source.read(@dnd_path)
    dir = tmp_dir()

    assert :ok = Source.write(source, dir)
    assert Source.read(dir) == {:ok, source}
  end

  test "write/2 skips optional files that are nil" do
    dir = tmp_dir()
    source = %Source{module: %{"module" => %{"name" => "X"}}}

    assert :ok = Source.write(source, dir)
    assert File.ls!(dir) == ["module.toml"]
  end

  test "Loader.load_source/1 builds the same system as Loader.load/1" do
    {:ok, source} = Source.read(@dnd_path)
    assert Loader.load_source(source) == Loader.load(@dnd_path)
  end
end
