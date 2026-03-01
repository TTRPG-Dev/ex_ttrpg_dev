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

  test "load/1 returns all six ability node groups" do
    {:ok, data} = Loader.load(dnd_path())
    attrs = ~w(strength dexterity constitution wisdom intelligence charisma)

    for attr <- attrs do
      assert Map.has_key?(data.nodes, {"ability", attr, "base_score"}),
             "Missing base_score for #{attr}"

      assert Map.has_key?(data.nodes, {"ability", attr, "total_score"}),
             "Missing total_score for #{attr}"

      assert Map.has_key?(data.nodes, {"ability", attr, "modifier"}),
             "Missing modifier for #{attr}"
    end
  end

  test "load/1 nodes have correct types" do
    {:ok, data} = Loader.load(dnd_path())

    assert %{type: :generated} = data.nodes[{"ability", "dexterity", "base_score"}]
    assert %{type: :accumulator} = data.nodes[{"ability", "dexterity", "total_score"}]
    assert %{type: :formula} = data.nodes[{"ability", "dexterity", "modifier"}]
  end

  test "load/1 skill nodes reference correct abilities" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.nodes, {"skill", "acrobatics", "modifier"})
    %{formula: formula} = data.nodes[{"skill", "acrobatics", "modifier"}]
    assert String.contains?(formula, "ability('dexterity')")

    assert Map.has_key?(data.nodes, {"skill", "athletics", "modifier"})
    %{formula: formula} = data.nodes[{"skill", "athletics", "modifier"}]
    assert String.contains?(formula, "ability('strength')")
  end

  test "load/1 returns rolling methods" do
    {:ok, data} = Loader.load(dnd_path())
    assert Map.has_key?(data.rolling_methods, "standard")
    assert Map.has_key?(data.rolling_methods, "hard")
    assert data.rolling_methods["standard"].dice == "4d6"
    assert data.rolling_methods["standard"].drop == "lowest"
    assert data.rolling_methods["standard"].default == true
  end

  test "load/1 returns concept metadata for abilities" do
    {:ok, data} = Loader.load(dnd_path())
    dex_meta = data.concept_metadata[{"ability", "dexterity"}]
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

    File.mkdir_p!(Path.join([dir, "concepts", "ability"]))
    File.mkdir_p!(Path.join([dir, "concepts", "feat"]))

    File.write!(Path.join(dir, "module.toml"), """
    [module]
    name = "Test System"
    slug = "test_system"
    version = "0.0.1"
    publisher = "Test"

    [[concept_type]]
    id = "ability"
    name = "Ability"

    [[concept_type]]
    id = "feat"
    name = "Feat"
    """)

    File.write!(Path.join([dir, "concepts", "ability", "abilities.toml"]), """
    [ability.strength]
    name = "Strength"
    base_score.type = "generated"
    base_score.method = "standard"
    total_score.type = "accumulator"
    total_score.base = "ability('strength').base_score"
    """)

    File.write!(Path.join([dir, "concepts", "feat", "feats.toml"]), """
    [feat.toughness]
    name = "Toughness"

    [[feat.toughness.contributes]]
    target = "ability('strength').total_score"
    value = 2
    """)

    try do
      assert {:ok, data} = Loader.load(dir)
      assert length(data.effects) == 1
      [effect] = data.effects
      assert effect.target == {"ability", "strength", "total_score"}
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

  test "load/1 registers equipment concept type" do
    {:ok, data} = Loader.load(dnd_path())

    concept_type_ids =
      data.module.concept_types
      |> Enum.map(& &1.id)

    assert "equipment" in concept_type_ids
  end

  test "load/1 returns concept metadata for armor" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.concept_metadata, {"equipment", "plate"})
    plate = data.concept_metadata[{"equipment", "plate"}]
    assert plate["name"] == "Plate"
    assert plate["category"] == "armor"
    assert plate["armor_type"] == "heavy"
    assert plate["ac_base"] == 18
    assert plate["ac_dex_bonus"] == false
    assert plate["strength_requirement"] == 15
    assert plate["stealth_disadvantage"] == true
    assert plate["cost"] == "1500 gp"
    assert plate["weight"] == 65

    shield = data.concept_metadata[{"equipment", "shield"}]
    assert shield["armor_type"] == "shield"
    assert shield["ac_bonus"] == 2
  end

  test "load/1 returns concept metadata for weapons" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.concept_metadata, {"equipment", "dagger"})
    dagger = data.concept_metadata[{"equipment", "dagger"}]
    assert dagger["name"] == "Dagger"
    assert dagger["category"] == "weapon"
    assert dagger["weapon_category"] == "simple"
    assert dagger["weapon_type"] == "melee"
    assert dagger["damage"] == "1d4"
    assert dagger["damage_type"] == "piercing"
    assert dagger["properties"] == ["finesse", "light", "thrown"]
    assert dagger["range_normal"] == 20
    assert dagger["range_long"] == 60

    longsword = data.concept_metadata[{"equipment", "longsword"}]
    assert longsword["weapon_category"] == "martial"
    assert longsword["versatile_damage"] == "1d10"
  end

  test "load/1 returns concept metadata for adventuring gear" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.concept_metadata, {"equipment", "torch"})
    torch = data.concept_metadata[{"equipment", "torch"}]
    assert torch["name"] == "Torch"
    assert torch["category"] == "adventuring_gear"
    assert torch["cost"] == "1 cp"
    assert torch["weight"] == 1

    assert Map.has_key?(data.concept_metadata, {"equipment", "spyglass"})
    assert Map.has_key?(data.concept_metadata, {"equipment", "arrows"})
  end

  test "load/1 returns all 13 armor items" do
    {:ok, data} = Loader.load(dnd_path())

    armor_ids =
      data.concept_metadata
      |> Enum.filter(fn {{type, _id}, meta} ->
        type == "equipment" and meta["category"] == "armor"
      end)
      |> Enum.map(fn {{_type, id}, _} -> id end)

    assert length(armor_ids) == 13
  end

  test "load/1 returns all 37 weapon items" do
    {:ok, data} = Loader.load(dnd_path())

    weapon_ids =
      data.concept_metadata
      |> Enum.filter(fn {{type, _id}, meta} ->
        type == "equipment" and meta["category"] == "weapon"
      end)
      |> Enum.map(fn {{_type, id}, _} -> id end)

    assert length(weapon_ids) == 37
  end
end
