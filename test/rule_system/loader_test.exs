defmodule ExTTRPGDev.RuleSystem.LoaderTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.{Loader, RuleModule}

  defp dnd_path do
    Application.app_dir(:ex_ttrpg_dev, "priv/system_configs/dnd_5e_srd")
  end

  test "load/1 succeeds for dnd_5e_srd" do
    assert {:ok, data} = Loader.load(dnd_path())
    assert %RuleModule{slug: "dnd_5e_srd"} = data.module
  end

  test "load/1 returns error for non-existent path" do
    assert {:error, _} = Loader.load("/nonexistent/path")
  end

  test "load/1 returns all six attribute node groups" do
    {:ok, data} = Loader.load(dnd_path())
    attrs = ~w(strength dexterity constitution wisdom intelligence charisma)

    for attr <- attrs do
      assert Map.has_key?(data.nodes, {"attr", attr, "base_score"}),
             "Missing base_score for #{attr}"

      assert Map.has_key?(data.nodes, {"attr", attr, "total_score"}),
             "Missing total_score for #{attr}"

      assert Map.has_key?(data.nodes, {"attr", attr, "modifier"}),
             "Missing modifier for #{attr}"
    end
  end

  test "load/1 nodes have correct types" do
    {:ok, data} = Loader.load(dnd_path())

    assert %{type: :generated} = data.nodes[{"attr", "dexterity", "base_score"}]
    assert %{type: :accumulator} = data.nodes[{"attr", "dexterity", "total_score"}]
    assert %{type: :formula} = data.nodes[{"attr", "dexterity", "modifier"}]
  end

  test "load/1 skill nodes reference correct attributes" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.nodes, {"skill", "acrobatics", "modifier"})
    %{formula: formula} = data.nodes[{"skill", "acrobatics", "modifier"}]
    assert String.contains?(formula, "attr('dexterity')")

    assert Map.has_key?(data.nodes, {"skill", "athletics", "modifier"})
    %{formula: formula} = data.nodes[{"skill", "athletics", "modifier"}]
    assert String.contains?(formula, "attr('strength')")
  end

  test "load/1 returns rolling methods" do
    {:ok, data} = Loader.load(dnd_path())
    assert Map.has_key?(data.rolling_methods, "standard")
    assert Map.has_key?(data.rolling_methods, "hard")
    assert data.rolling_methods["standard"].dice == "4d6"
    assert data.rolling_methods["standard"].drop == "lowest"
    assert data.rolling_methods["standard"].default == true
  end

  test "load/1 returns concept metadata for attributes" do
    {:ok, data} = Loader.load(dnd_path())
    dex_meta = data.concept_metadata[{"attr", "dexterity"}]
    assert dex_meta["name"] == "Dexterity"
    assert dex_meta["abbreviation"] == "DEX"
  end

  test "load/1 returns concept metadata for languages" do
    {:ok, data} = Loader.load(dnd_path())
    assert Map.has_key?(data.concept_metadata, {"language", "common"})
  end

  test "load!/1 raises for non-existent path" do
    assert_raise RuntimeError, ~r/Failed to load rule system/, fn ->
      Loader.load!("/nonexistent/path")
    end
  end

  test "load/1 parses contributes entries into the effects list" do
    dir =
      System.tmp_dir!() |> Path.join("ex_ttrpg_loader_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    File.write!(Path.join(dir, "module.toml"), """
    [module]
    name = "Test System"
    slug = "test_system"
    version = "0.0.1"
    publisher = "Test"

    [[concept_type]]
    id = "attr"
    name = "Attribute"

    [[concept_type]]
    id = "feat"
    name = "Feat"
    """)

    File.write!(Path.join(dir, "attributes.toml"), """
    [attr.strength]
    name = "Strength"
    base_score.type = "generated"
    base_score.method = "standard"
    total_score.type = "accumulator"
    total_score.base = "attr('strength').base_score"
    """)

    File.write!(Path.join(dir, "feats.toml"), """
    [feat.toughness]
    name = "Toughness"

    [[feat.toughness.contributes]]
    target = "attr('strength').total_score"
    value = 2
    """)

    try do
      assert {:ok, data} = Loader.load(dir)
      assert length(data.effects) == 1
      [effect] = data.effects
      assert effect.target == {"attr", "strength", "total_score"}
      assert effect.value == 2
    after
      File.rm_rf!(dir)
    end
  end

  test "load/1 returns 18 skill nodes" do
    {:ok, data} = Loader.load(dnd_path())

    skill_nodes =
      data.nodes
      |> Map.keys()
      |> Enum.count(fn {type, _id, _field} -> type == "skill" end)

    assert skill_nodes == 18
  end
end
