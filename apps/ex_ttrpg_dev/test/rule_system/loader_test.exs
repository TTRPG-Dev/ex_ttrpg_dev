defmodule ExTTRPGDev.RuleSystem.LoaderTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.{InventoryRules, Loader, RuleModule}

  defp dnd_path do
    Application.app_dir(:ex_ttrpg_dev, "priv/system_configs/dnd_5e_srd")
  end

  # Creates a temporary rule system directory with a minimal module.toml,
  # calls fun/1 with the dir path, then cleans up.
  defp with_tmp_system(concept_types \\ ["ability", "feat"], fun) do
    dir =
      System.tmp_dir!() |> Path.join("ex_ttrpg_loader_test_#{System.unique_integer([:positive])}")

    File.mkdir_p!(dir)

    concept_types_toml =
      Enum.map_join(concept_types, "\n", fn t ->
        "\n[[concept_type]]\nid = \"#{t}\"\nname = \"#{String.capitalize(t)}\""
      end)

    File.write!(Path.join(dir, "module.toml"), """
    [module]
    name = "Test System"
    slug = "test_system"
    version = "0.0.1"
    #{concept_types_toml}
    """)

    try do
      fun.(dir)
    after
      File.rm_rf!(dir)
    end
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

  test "load/1 skill nodes are accumulators referencing correct abilities" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.nodes, {"skill", "acrobatics", "modifier"})
    %{type: :accumulator, base: base} = data.nodes[{"skill", "acrobatics", "modifier"}]
    assert String.contains?(base, "ability('dexterity')")

    assert Map.has_key?(data.nodes, {"skill", "athletics", "modifier"})
    %{type: :accumulator, base: base} = data.nodes[{"skill", "athletics", "modifier"}]
    assert String.contains?(base, "ability('strength')")
  end

  test "load/1 returns the standard rolling method" do
    {:ok, data} = Loader.load(dnd_path())
    assert Map.has_key?(data.rolling_methods, "standard")
  end

  test "load/1 standard rolling method has correct configuration" do
    {:ok, data} = Loader.load(dnd_path())
    standard = data.rolling_methods["standard"]
    assert standard.dice == "4d6"
    assert standard.drop == "lowest"
    assert standard.default == true
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
    with_tmp_system(fn dir ->
      File.mkdir_p!(Path.join([dir, "concepts", "ability"]))
      File.mkdir_p!(Path.join([dir, "concepts", "feat"]))

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
      when = "item.equipped"

      [[feat.toughness.contributes]]
      target = "ability('strength').total_score"
      value = 1
      """)

      assert {:ok, data} = Loader.load(dir)
      assert length(data.effects) == 2
      [conditional, unconditional] = data.effects
      assert conditional.target == {"ability", "strength", "total_score"}
      assert conditional.value == 2
      assert conditional.when == "item.equipped"
      assert unconditional.when == nil
    end)
  end

  test "load/1 returns inventory_rules for dnd_5e_srd" do
    assert {:ok, data} = Loader.load(dnd_path())
    assert %InventoryRules{} = data.inventory_rules
    assert InventoryRules.inventoriable?(data.inventory_rules, "equipment")
    refute InventoryRules.inventoriable?(data.inventory_rules, "language")
    assert Map.has_key?(data.inventory_rules.schema, "equipped")
    refute Map.has_key?(data.inventory_rules.schema, "condition")
  end

  test "load/1 parses inventory_rules.toml when present" do
    with_tmp_system(["equipment"], fn dir ->
      File.write!(Path.join(dir, "inventory_rules.toml"), """
      [inventory]
      inventoriable_types = ["equipment"]

      [inventory_item_schema.equipped]
      type = "boolean"
      default = false
      """)

      assert {:ok, data} = Loader.load(dir)
      assert InventoryRules.inventoriable?(data.inventory_rules, "equipment")
      refute InventoryRules.inventoriable?(data.inventory_rules, "language")
      assert %{type: :boolean, default: false} = data.inventory_rules.schema["equipped"]
    end)
  end

  test "load/1 returns 18 skill nodes" do
    {:ok, data} = Loader.load(dnd_path())

    skill_nodes =
      data.nodes
      |> Map.keys()
      |> Enum.count(fn {type, _id, _field} -> type == "skill" end)

    assert skill_nodes == 18
  end

  test "load/1 registers equipment and currency concept types" do
    {:ok, data} = Loader.load(dnd_path())

    concept_type_ids = Enum.map(data.module.concept_types, & &1.id)

    assert "equipment" in concept_type_ids
    assert "currency" in concept_type_ids
  end

  test "load/1 registers saving_throw concept type" do
    {:ok, data} = Loader.load(dnd_path())

    concept_type_ids = Enum.map(data.module.concept_types, & &1.id)
    assert "saving_throw" in concept_type_ids
  end

  test "load/1 returns all six saving throw modifier nodes" do
    {:ok, data} = Loader.load(dnd_path())
    abilities = ~w(strength dexterity constitution wisdom intelligence charisma)

    for ability <- abilities do
      assert Map.has_key?(data.nodes, {"saving_throw", ability, "modifier"}),
             "Missing modifier for saving_throw #{ability}"
    end
  end

  test "load/1 saving throw modifier nodes are accumulators referencing the correct ability" do
    {:ok, data} = Loader.load(dnd_path())

    for ability <- ~w(strength dexterity constitution wisdom intelligence charisma) do
      node = data.nodes[{"saving_throw", ability, "modifier"}]
      assert %{type: :accumulator} = node
      assert String.contains?(node.base, "ability('#{ability}').modifier")
    end
  end

  test "load/1 registers character_trait concept type" do
    {:ok, data} = Loader.load(dnd_path())
    concept_type_ids = Enum.map(data.module.concept_types, & &1.id)
    assert "character_trait" in concept_type_ids
  end

  test "load/1 returns proficiency_bonus as an accumulator referencing character_level" do
    {:ok, data} = Loader.load(dnd_path())
    node = data.nodes[{"character_trait", "proficiency_bonus", "bonus"}]
    assert %{type: :accumulator, base: base} = node
    assert String.contains?(base, "character_trait('character_level').level")
  end

  test "load/1 returns experience_points as an accumulator node" do
    {:ok, data} = Loader.load(dnd_path())

    assert %{type: :accumulator, base: "0"} =
             data.nodes[{"character_trait", "experience_points", "total"}]
  end

  test "load/1 returns character_level as a mapping node with 20 XP steps" do
    {:ok, data} = Loader.load(dnd_path())
    node = data.nodes[{"character_trait", "character_level", "level"}]
    assert %{type: :mapping, steps: steps} = node
    assert length(steps) == 20
    assert List.first(steps) == [0, 1]
    assert List.last(steps) == [305_000, 20]
  end

  test "load/1 returns saving_throw roll definition" do
    {:ok, data} = Loader.load(dnd_path())

    saving_throw_roll =
      Enum.find_value(data.concept_metadata, fn {{type, _id}, meta} ->
        if type == "roll" and meta["target_type"] == "saving_throw", do: meta
      end)

    assert saving_throw_roll["dice"] == "1d20"
    assert saving_throw_roll["bonus_field"] == "modifier"
  end

  test "load/1 returns all 5 currencies with correct conversion rates" do
    {:ok, data} = Loader.load(dnd_path())
    currency_meta = fn id -> data.concept_metadata[{"currency", id}] end

    for {id, rate} <- [copper: 1, silver: 10, electrum: 50, gold: 100, platinum: 1000] do
      assert currency_meta.(to_string(id))["in_copper"] == rate
    end

    assert currency_meta.("gold")["abbreviation"] == "gp"
  end

  test "load/1 returns concept metadata for armor" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.concept_metadata, {"equipment", "plate"})
    plate = data.concept_metadata[{"equipment", "plate"}]

    assert %{
             "name" => "Plate",
             "category" => "armor",
             "armor_type" => "heavy",
             "ac_base" => 18,
             "ac_dex_bonus" => false,
             "strength_requirement" => 15,
             "stealth_disadvantage" => true,
             "weight" => 65
           } = plate

    assert_cost(plate, 1500, "gp")

    shield = data.concept_metadata[{"equipment", "shield"}]
    assert shield["armor_type"] == "shield"
    assert shield["ac_bonus"] == 2
  end

  test "load/1 returns concept metadata for weapons" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.concept_metadata, {"equipment", "dagger"})
    dagger = data.concept_metadata[{"equipment", "dagger"}]

    assert %{
             "name" => "Dagger",
             "category" => "weapon",
             "weapon_category" => "simple",
             "weapon_type" => "melee",
             "damage" => "1d4",
             "damage_type" => "piercing",
             "properties" => ["finesse", "light", "thrown"],
             "range_normal" => 20,
             "range_long" => 60
           } = dagger

    assert_cost(dagger, 2, "gp")

    longsword = data.concept_metadata[{"equipment", "longsword"}]
    assert longsword["weapon_category"] == "martial"
    assert longsword["versatile_damage"] == "1d10"
  end

  test "load/1 returns concept metadata for adventuring gear" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.concept_metadata, {"equipment", "torch"})
    torch = data.concept_metadata[{"equipment", "torch"}]

    assert %{"name" => "Torch", "category" => "adventuring_gear", "weight" => 1} = torch
    assert_cost(torch, 1, "cp")

    assert Map.has_key?(data.concept_metadata, {"equipment", "spyglass"})
    assert Map.has_key?(data.concept_metadata, {"equipment", "arrows"})
  end

  test "load/1 returns all 13 armor items" do
    {:ok, data} = Loader.load(dnd_path())
    assert count_equipment_by_category(data, "armor") == 13
  end

  test "load/1 returns all 37 weapon items" do
    {:ok, data} = Loader.load(dnd_path())
    assert count_equipment_by_category(data, "weapon") == 37
  end

  test "load/1 returns concept metadata for tools" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.concept_metadata, {"equipment", "thieves_tools"})
    thieves_tools = data.concept_metadata[{"equipment", "thieves_tools"}]

    assert %{"name" => "Thieves' Tools", "category" => "tool", "tool_type" => "kit"} =
             thieves_tools

    assert_cost(thieves_tools, 25, "gp")

    assert data.concept_metadata[{"equipment", "lute"}]["tool_type"] == "musical_instrument"
    assert data.concept_metadata[{"equipment", "smiths_tools"}]["tool_type"] == "artisans_tool"
  end

  test "load/1 returns all 35 tool items" do
    {:ok, data} = Loader.load(dnd_path())
    assert count_equipment_by_category(data, "tool") == 35
  end

  test "load/1 returns concept metadata for trade goods" do
    {:ok, data} = Loader.load(dnd_path())

    assert Map.has_key?(data.concept_metadata, {"equipment", "platinum"})
    platinum = data.concept_metadata[{"equipment", "platinum"}]

    assert %{"name" => "Platinum (1 lb.)", "category" => "trade_good"} = platinum
    assert_cost(platinum, 500, "gp")

    assert Map.has_key?(data.concept_metadata, {"equipment", "wheat"})
  end

  test "load/1 returns all 23 trade good items" do
    {:ok, data} = Loader.load(dnd_path())
    assert count_equipment_by_category(data, "trade_good") == 23
  end

  test "load/1 returns race concept metadata" do
    {:ok, data} = Loader.load(dnd_path())

    for race <- ~w(human dwarf elf halfling gnome dragonborn half_elf half_orc tiefling) do
      assert Map.has_key?(data.concept_metadata, {"race", race}), "Missing race: #{race}"
    end
  end

  test "load/1 returns subrace metadata for races with subraces" do
    {:ok, data} = Loader.load(dnd_path())

    subraces = ~w(hill_dwarf high_elf lightfoot_halfling rock_gnome)

    for subrace <- subraces do
      assert Map.has_key?(data.concept_metadata, {"race", subrace}), "Missing subrace: #{subrace}"
    end
  end

  test "load/1 parses fighter starting_weapon as an equipment choice granting inventory" do
    {:ok, data} = Loader.load(dnd_path())
    fighter = data.concept_metadata[{"class", "fighter"}]
    weapon_choice = fighter["choices"]["starting_weapon"]
    assert weapon_choice["grants_to"] == "inventory"
    assert weapon_choice["type"] == "equipment"
    assert "longsword" in weapon_choice["options"]
  end

  test "load/1 parses acolyte static starting_equipment" do
    {:ok, data} = Loader.load(dnd_path())
    acolyte = data.concept_metadata[{"background", "acolyte"}]
    equipment = acolyte["starting_equipment"]
    assert is_list(equipment)
    assert Enum.any?(equipment, &(&1["id"] == "holy_symbol_amulet"))
    assert Enum.any?(equipment, &(&1["id"] == "backpack"))
  end

  test "load/1 parses choices into race metadata" do
    {:ok, data} = Loader.load(dnd_path())

    subrace_choice = data.concept_metadata[{"race", "dwarf"}]["choices"]["subrace"]
    assert %{"type" => "race", "required" => true, "options" => options} = subrace_choice
    assert options == ["hill_dwarf"]
  end

  test "load/1 parses race contributes into the effects list" do
    {:ok, data} = Loader.load(dnd_path())

    human_bonuses =
      Enum.filter(data.effects, fn e -> e.source == {"race", "human"} end)

    assert length(human_bonuses) == 7

    constitution_bonus =
      Enum.find(data.effects, fn e ->
        e.source == {"race", "dwarf"} and
          e.target == {"ability", "constitution", "total_score"}
      end)

    assert constitution_bonus != nil
    assert constitution_bonus.value == 2
    assert constitution_bonus.when == nil
  end

  defp assert_cost(item, amount, currency) do
    assert item["cost"]["amount"] == amount
    assert item["cost"]["currency"] == currency
  end

  defp count_equipment_by_category(data, category) do
    Enum.count(data.concept_metadata, fn {{type, _id}, meta} ->
      type == "equipment" and meta["category"] == category
    end)
  end
end
