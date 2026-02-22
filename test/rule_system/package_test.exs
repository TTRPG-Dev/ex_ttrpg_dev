defmodule ExTTRPGDev.RuleSystem.PackageTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.Package

  @valid_map %{
    "package" => %{
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
    assert {:ok, %Package{} = pkg} = Package.from_map(@valid_map)
    assert pkg.name == "Test System"
    assert pkg.slug == "test_system"
    assert pkg.version == "1.0.0"
    assert pkg.publisher == "Test Publisher"
  end

  test "from_map/1 parses concept types" do
    {:ok, pkg} = Package.from_map(@valid_map)
    assert length(pkg.concept_types) == 2
    assert Enum.any?(pkg.concept_types, &(&1.id == "attr" and &1.name == "Attribute"))
    assert Enum.any?(pkg.concept_types, &(&1.id == "skill" and &1.name == "Skill"))
  end

  test "from_map/1 returns error when name is missing" do
    map =
      put_in(@valid_map, ["package", "name"], nil)
      |> Map.update!("package", &Map.delete(&1, "name"))

    assert {:error, {:missing_required_key, "name"}} = Package.from_map(map)
  end

  test "from_map/1 returns error when slug is missing" do
    map = Map.update!(@valid_map, "package", &Map.delete(&1, "slug"))
    assert {:error, {:missing_required_key, "slug"}} = Package.from_map(map)
  end

  test "from_map/1 returns error when package key is missing" do
    assert {:error, {:missing_required_key, "package"}} = Package.from_map(%{})
  end

  test "from_map/1 handles missing concept_type gracefully" do
    map = Map.delete(@valid_map, "concept_type")
    assert {:ok, %Package{concept_types: []}} = Package.from_map(map)
  end

  test "concept_type_ids/1 returns a MapSet of ids" do
    {:ok, pkg} = Package.from_map(@valid_map)
    ids = Package.concept_type_ids(pkg)
    assert MapSet.member?(ids, "attr")
    assert MapSet.member?(ids, "skill")
    refute MapSet.member?(ids, "item")
  end
end
