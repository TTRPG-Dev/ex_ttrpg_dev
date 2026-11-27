defmodule ExTTRPGDev.RuleSystem.ClassLevelNodesTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias ExTTRPGDev.RuleSystem.{Graph, Loader, Node}
  alias ExTTRPGDevTest.ClassLevelsFixture

  @level_node {"character_trait", "character_level", "level"}

  defp load_modified_fixture(modify), do: ClassLevelsFixture.load_modified(modify)

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
        ClassLevelsFixture.replace_in(dir, "module.toml", ~s(class_concept_type = "class"), "")

        ClassLevelsFixture.replace_in(
          dir,
          "concepts/classes.toml",
          ~s{"class('fighter').level"},
          ~s{"1"}
        )
      end)

    refute Map.has_key?(data.nodes, {"class", "fighter", "level"})
  end

  test "a class_concept_type that isn't a character choice is rejected" do
    assert {:error, {:module_parse_error, {:class_concept_type_not_a_character_choice, "class"}}} =
             load_modified_fixture(fn dir ->
               ClassLevelsFixture.replace_in(
                 dir,
                 "character_building.toml",
                 ~s(concept_type = "class"),
                 ~s(concept_type = "skill")
               )
             end)
  end

  test "a multiclass table outside the class concept type is warned about" do
    log =
      capture_log(fn ->
        {:ok, _data} =
          load_modified_fixture(fn dir ->
            ClassLevelsFixture.replace_in(
              dir,
              "concepts/core.toml",
              ~s([skill.arcana]\nname = "Arcana"),
              ~s([skill.arcana]\nname = "Arcana"\n\n[skill.arcana.multiclass]\nprerequisite = "true")
            )
          end)
      end)

    assert log =~ ~s|"multiclass" table on "skill" concept(s)|
    assert log =~ "arcana"
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

  describe "multiclass table validation" do
    defp build_with_multiclass(table_toml) do
      with {:ok, data} <-
             load_modified_fixture(fn dir ->
               ClassLevelsFixture.replace_in(
                 dir,
                 "concepts/classes.toml",
                 ~s|[class.wizard.multiclass]\nprerequisite = "ability('intelligence').score >= 13"|,
                 "[class.wizard.multiclass]\n" <> table_toml
               )
             end) do
        Graph.build(data)
      end
    end

    test "accepts the fixture's tables" do
      assert {:ok, _} = build_with_multiclass(~s(prerequisite = "true"))
    end

    test "rejects a prerequisite that doesn't parse" do
      assert {:error, {:invalid_multiclass_table, message}} =
               build_with_multiclass(~s|prerequisite = "ability('intelligence').score >="|)

      assert message =~ "class('wizard').multiclass.prerequisite"
    end

    test "rejects a prerequisite referencing an undefined node" do
      assert {:error, {:undefined_ref, message}} =
               build_with_multiclass(~s|prerequisite = "ability('wisdom').score >= 13"|)

      assert message =~ "ability('wisdom').score"
    end

    test "rejects choices the class doesn't declare" do
      assert {:error, {:invalid_multiclass_table, message}} =
               build_with_multiclass(~s(choices = ["skill_1"]))

      assert message =~ ~s("skill_1")
    end
  end
end
