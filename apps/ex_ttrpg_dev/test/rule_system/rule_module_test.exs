defmodule ExTTRPGDev.RuleSystem.RuleModuleTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.RuleModule

  @valid_map %{
    "module" => %{
      "name" => "Test System",
      "slug" => "test_system",
      "version" => "1.0.0",
      "publisher" => "Test Publisher"
    },
    "concept_type" => [
      %{"id" => "attr", "name" => "Attribute"},
      %{"id" => "skill", "name" => "Skill"}
    ]
  }

  test "from_map/1 returns ok with valid map" do
    assert {:ok, %RuleModule{} = pkg} = RuleModule.from_map(@valid_map)
    assert pkg.name == "Test System"
    assert pkg.slug == "test_system"
    assert pkg.version == "1.0.0"
    assert pkg.publisher == "Test Publisher"
  end

  test "from_map/1 parses concept types" do
    {:ok, pkg} = RuleModule.from_map(@valid_map)
    assert length(pkg.concept_types) == 2
    assert Enum.any?(pkg.concept_types, &(&1.id == "attr" and &1.name == "Attribute"))
    assert Enum.any?(pkg.concept_types, &(&1.id == "skill" and &1.name == "Skill"))
  end

  test "from_map/1 returns error when name is missing" do
    map =
      put_in(@valid_map, ["module", "name"], nil)
      |> Map.update!("module", &Map.delete(&1, "name"))

    assert {:error, {:missing_required_key, "name"}} = RuleModule.from_map(map)
  end

  test "from_map/1 returns error when slug is missing" do
    map = Map.update!(@valid_map, "module", &Map.delete(&1, "slug"))
    assert {:error, {:missing_required_key, "slug"}} = RuleModule.from_map(map)
  end

  test "from_map/1 returns error when module key is missing" do
    assert {:error, {:missing_required_key, "module"}} = RuleModule.from_map(%{})
  end

  test "from_map/1 handles missing concept_type gracefully" do
    map = Map.delete(@valid_map, "concept_type")
    assert {:ok, %RuleModule{concept_types: []}} = RuleModule.from_map(map)
  end

  test "from_map/1 defaults metadata_contributions to empty list" do
    {:ok, pkg} = RuleModule.from_map(@valid_map)
    assert pkg.metadata_contributions == []
  end

  test "from_map/1 parses level_node when present" do
    map = put_in(@valid_map, ["module", "level_node"], "character_trait('character_level').level")
    {:ok, pkg} = RuleModule.from_map(map)
    assert pkg.level_node == "character_trait('character_level').level"
  end

  test "from_map/1 defaults level_node to nil when absent" do
    {:ok, pkg} = RuleModule.from_map(@valid_map)
    assert pkg.level_node == nil
  end

  test "from_map/1 parses metadata_contributions with label_filters" do
    map =
      Map.put(@valid_map, "metadata_contributions", [
        %{
          "from_type" => "class",
          "from_field" => "weapon_proficiencies",
          "to_type" => "equipment",
          "to_field" => "is_proficient",
          "value" => 1,
          "label_filters" => [
            %{
              "label" => "Simple Weapons",
              "filter_field" => "weapon_category",
              "filter_value" => "simple"
            }
          ]
        }
      ])

    {:ok, pkg} = RuleModule.from_map(map)
    assert length(pkg.metadata_contributions) == 1

    [contrib] = pkg.metadata_contributions
    assert contrib.from_type == "class"
    assert contrib.from_field == "weapon_proficiencies"
    assert contrib.to_type == "equipment"
    assert contrib.to_field == "is_proficient"
    assert contrib.value == 1

    assert length(contrib.label_filters) == 1
    [filter] = contrib.label_filters
    assert filter.label == "Simple Weapons"
    assert filter.filter_field == "weapon_category"
    assert filter.filter_value == "simple"
  end

  test "from_map/1 parses metadata_contributions with empty label_filters" do
    map =
      Map.put(@valid_map, "metadata_contributions", [
        %{
          "from_type" => "class",
          "from_field" => "weapon_proficiencies",
          "to_type" => "equipment",
          "to_field" => "is_proficient",
          "value" => 1,
          "label_filters" => []
        }
      ])

    {:ok, pkg} = RuleModule.from_map(map)
    [contrib] = pkg.metadata_contributions
    assert contrib.label_filters == []
  end

  test "concept_type_ids/1 returns a MapSet of ids" do
    {:ok, pkg} = RuleModule.from_map(@valid_map)
    ids = RuleModule.concept_type_ids(pkg)
    assert MapSet.member?(ids, "attr")
    assert MapSet.member?(ids, "skill")
    refute MapSet.member?(ids, "item")
  end
end
