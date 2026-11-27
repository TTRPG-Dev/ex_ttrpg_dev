defmodule ExTTRPGDev.RuleSystem.ClassLevelNodesTest do
  use ExUnit.Case, async: true

  alias ExTTRPGDev.RuleSystem.{Graph, Loader, Node}
  alias ExTTRPGDevTest.ClassLevelsFixture

  @level_node {"character_trait", "character_level", "level"}

  # Copies the fixture to a temp dir, lets `fun` modify it, and loads it.
  defp load_modified_fixture(fun) do
    dir =
      Path.join(System.tmp_dir!(), "ex_ttrpg_class_levels_#{System.unique_integer([:positive])}")

    File.cp_r!(ClassLevelsFixture.path(), dir)

    try do
      fun.(dir)
      Loader.load(dir)
    after
      File.rm_rf!(dir)
    end
  end

  test "every concept of the class concept type gets a level accumulator with base 0" do
    {:ok, data} = Loader.load(ClassLevelsFixture.path())

    for id <- ~w(fighter wizard champion) do
      assert %Node{type: :accumulator, base: "0"} = data.nodes[{"class", id, "level"}]
    end

    refute Map.has_key?(data.nodes, {"ability", "strength", "level"})
  end

  test "class level nodes depend on the module's level node" do
    {:ok, data} = Loader.load(ClassLevelsFixture.path())
    {:ok, built} = Graph.build(data)

    assert Elixir.Graph.edge(built.graph, @level_node, {"class", "wizard", "level"})
  end

  test "formulas can reference a class's level" do
    {:ok, data} = Loader.load(ClassLevelsFixture.path())
    {:ok, built} = Graph.build(data)

    assert Elixir.Graph.edge(
             built.graph,
             {"class", "fighter", "level"},
             {"class", "fighter", "second_wind_bonus"}
           )
  end

  test "no level nodes are added without a class_concept_type" do
    {:ok, data} =
      load_modified_fixture(fn dir ->
        module = Path.join(dir, "module.toml")

        File.write!(
          module,
          String.replace(File.read!(module), ~s(class_concept_type = "class"), "")
        )

        classes = Path.join(dir, "concepts/classes.toml")

        File.write!(
          classes,
          String.replace(File.read!(classes), ~s{"class('fighter').level"}, ~s{"1"})
        )
      end)

    refute Map.has_key?(data.nodes, {"class", "fighter", "level"})
  end

  test "a class that authors its own level field is rejected" do
    assert {:error, {:reserved_class_level_field, "class('wizard').level"}} =
             load_modified_fixture(fn dir ->
               File.write!(
                 Path.join(dir, "concepts/classes.toml"),
                 ~s(\n[class.wizard.level]\nformula = "1"\n),
                 [:append]
               )
             end)
  end
end
