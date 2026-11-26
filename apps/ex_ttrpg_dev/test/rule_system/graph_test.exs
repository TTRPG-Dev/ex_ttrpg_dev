defmodule ExTTRPGDev.RuleSystem.GraphTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.{Effect, Graph, Loader, Node}

  defp graph_data(nodes, effects \\ []) do
    %{nodes: nodes, rolling_methods: %{}, concept_metadata: %{}, effects: effects}
  end

  defp minimal_loader_data do
    graph_data(%{
      {"attr", "strength", "base_score"} => %Node{type: :generated, method: "standard"},
      {"attr", "strength", "total_score"} => %Node{
        type: :accumulator,
        base: "attr('strength').base_score"
      },
      {"attr", "strength", "modifier"} => %Node{
        type: :formula,
        formula: "floor((attr('strength').total_score - 10) / 2)"
      }
    })
  end

  defp with_choices(concept_metadata) do
    %{nodes: %{}, rolling_methods: %{}, effects: [], concept_metadata: concept_metadata}
  end

  defp dnd_path do
    Application.app_dir(:ex_ttrpg_dev, "priv/system_configs/dnd_5e_srd")
  end

  defp contributes_choice_data(value) do
    %{
      nodes: %{
        {"ability", "strength", "base"} => %Node{type: :generated, method: "standard"},
        {"ability", "strength", "total_score"} => %Node{type: :accumulator, base: "0"}
      },
      rolling_methods: %{},
      effects: [],
      concept_metadata: %{
        {"race", "half_elf"} => %{
          "choices" => %{
            "ability_increase" => %{
              "type" => "ability",
              "options" => ["strength"],
              "contributes_field" => "total_score",
              "contributes_value" => value
            }
          }
        },
        {"ability", "strength"} => %{"name" => "Strength"}
      }
    }
  end

  test "build/1 accepts a numeric choice contributes_value" do
    assert {:ok, _system} = Graph.build(contributes_choice_data(1))
    assert {:ok, _system} = Graph.build(contributes_choice_data(1.5))
  end

  test "build/1 adds edges for a formula choice contributes_value" do
    assert {:ok, system} = Graph.build(contributes_choice_data("ability('strength').base"))

    assert Elixir.Graph.edge(
             system.graph,
             {"ability", "strength", "base"},
             {"ability", "strength", "total_score"}
           )
  end

  test "build/1 rejects a formula choice contributes_value with undefined refs" do
    assert {:error, {:undefined_ref, _}} =
             Graph.build(contributes_choice_data("ability('strength').missing"))
  end

  test "build/1 succeeds on valid minimal data" do
    assert {:ok, system} = Graph.build(minimal_loader_data())
    assert is_map(system.graph)
    assert map_size(system.nodes) == 3
  end

  test "build/1 rejects a non-tuple effect target" do
    effect = %Effect{source: {"attr", "strength"}, target: "attr(strength).total_score", value: 2}
    data = Map.put(minimal_loader_data(), :effects, [effect])

    assert {:error, {:invalid_effect_target, "attr(strength).total_score"}} = Graph.build(data)
  end

  test "build/1 returns error for undefined reference" do
    bad_data =
      graph_data(%{
        {"attr", "strength", "modifier"} => %Node{
          type: :formula,
          formula: "attr('strength').total_score"
        }
      })

    assert {:error, {:undefined_ref, _}} = Graph.build(bad_data)
  end

  test "build/1 detects cycles" do
    cyclic_data =
      graph_data(%{
        {"attr", "a", "val"} => %Node{type: :formula, formula: "attr('b').val"},
        {"attr", "b", "val"} => %Node{type: :formula, formula: "attr('a').val"}
      })

    assert {:error, {:cycle_detected, _}} = Graph.build(cyclic_data)
  end

  test "topological_order/1 returns base_score before modifier" do
    {:ok, system} = Graph.build(minimal_loader_data())
    order = Graph.topological_order(system)

    base_idx = Enum.find_index(order, &(&1 == {"attr", "strength", "base_score"}))
    total_idx = Enum.find_index(order, &(&1 == {"attr", "strength", "total_score"}))
    mod_idx = Enum.find_index(order, &(&1 == {"attr", "strength", "modifier"}))

    assert base_idx < total_idx
    assert total_idx < mod_idx
  end

  @prof_bonus_effect %Effect{
    source: {"class", "fighter", nil},
    target: {"save", "str", "modifier"},
    value: "trait('prof').bonus"
  }

  test "build/1 adds edge from formula-valued effect's ref to its target" do
    data =
      graph_data(
        %{
          {"trait", "prof", "bonus"} => %Node{type: :accumulator, base: "2"},
          {"save", "str", "modifier"} => %Node{type: :accumulator, base: "0"}
        },
        [@prof_bonus_effect]
      )

    assert {:ok, system} = Graph.build(data)
    order = Graph.topological_order(system)
    prof_idx = Enum.find_index(order, &(&1 == {"trait", "prof", "bonus"}))
    save_idx = Enum.find_index(order, &(&1 == {"save", "str", "modifier"}))
    assert prof_idx < save_idx
  end

  test "build/1 returns error for undefined ref in formula-valued effect" do
    data =
      graph_data(
        %{{"save", "str", "modifier"} => %Node{type: :accumulator, base: "0"}},
        [@prof_bonus_effect]
      )

    assert {:error, {:undefined_ref, _}} = Graph.build(data)
  end

  @armor_gated_effect %Effect{
    source: {"class", "barbarian", nil},
    target: {"trait", "speed", "amount"},
    value: 10,
    when: "trait('armor').heavy == 0"
  }

  test "build/1 adds edge from a `when` condition's ref to the effect's target" do
    data =
      graph_data(
        %{
          {"trait", "armor", "heavy"} => %Node{type: :accumulator, base: "0"},
          {"trait", "speed", "amount"} => %Node{type: :accumulator, base: "30"}
        },
        [@armor_gated_effect]
      )

    assert {:ok, system} = Graph.build(data)

    assert Elixir.Graph.edge(
             system.graph,
             {"trait", "armor", "heavy"},
             {"trait", "speed", "amount"}
           ) !=
             nil
  end

  test "build/1 returns error for undefined ref in an effect's `when` condition" do
    data =
      graph_data(
        %{{"trait", "speed", "amount"} => %Node{type: :accumulator, base: "30"}},
        [@armor_gated_effect]
      )

    assert {:error, {:undefined_ref, message}} = Graph.build(data)
    assert message =~ "trait('armor').heavy"
  end

  test "build/1 adds no edges for item placeholders in an effect's `when` condition" do
    effect = %Effect{
      source: {"item", "ring", nil},
      target: {"attr", "strength", "total_score"},
      value: 2,
      when: "item.equipped"
    }

    data = Map.put(minimal_loader_data(), :effects, [effect])

    assert {:ok, system} = Graph.build(data)

    assert Elixir.Graph.in_edges(system.graph, {"attr", "strength", "total_score"}) |> length() ==
             1
  end

  test "build/1 returns error for undefined contribution target" do
    data =
      graph_data(
        %{{"attr", "strength", "base_score"} => %Node{type: :generated, method: "standard"}},
        [
          %Effect{
            source: {"item", "ring", nil},
            target: {"attr", "strength", "nonexistent"},
            value: 2
          }
        ]
      )

    assert {:error, {:undefined_effect_target, _}} = Graph.build(data)
  end

  test "build/1 succeeds when all choice options reference valid concepts" do
    data =
      with_choices(%{
        {"race", "human"} => %{
          "choices" => %{
            "language" => %{"type" => "language", "options" => ["common", "elvish"]}
          }
        },
        {"language", "common"} => %{"name" => "Common"},
        {"language", "elvish"} => %{"name" => "Elvish"}
      })

    assert {:ok, _} = Graph.build(data)
  end

  test "build/1 returns error for choice referencing undefined concept type" do
    data =
      with_choices(%{
        {"race", "human"} => %{
          "choices" => %{
            "language" => %{"type" => "nonexistent_type", "options" => ["common"]}
          }
        }
      })

    assert {:error, {:undefined_choice_type, _}} = Graph.build(data)
  end

  test "build/1 returns error for choice option not found in its type" do
    data =
      with_choices(%{
        {"race", "human"} => %{
          "choices" => %{
            "language" => %{"type" => "language", "options" => ["common", "typo_lang"]}
          }
        },
        {"language", "common"} => %{"name" => "Common"}
      })

    assert {:error, {:undefined_choice_option, _}} = Graph.build(data)
  end

  test "integration: build succeeds for full dnd_5e_srd" do
    {:ok, loader_data} = Loader.load(dnd_path())
    assert {:ok, system} = Graph.build(loader_data)

    # 6 abilities * 3 fields + 18 skills * 1 field + 6 saving throws * 1 field + 14 character trait fields
    # + 37 weapons * 2 fields (is_proficient, attack_bonus) = 130 nodes
    # + 9 full_caster_slots + 5 half_caster_slots + 9 spell_slots + 2 pact_magic + 2 warlock pact mapping = 27 nodes
    # + 3 character_trait accumulators (cantrips_known, spells_known, max_spell_level)
    # + 17 class mapping nodes (cantrips/spells known/max spell level per spellcasting class) = 20 nodes (total: 177)
    # + 1 untracked node (equipment or class field not listed above) = 178 nodes
    # + 12 class asi_slots mapping nodes + 1 character_trait asi_count accumulator = 13 nodes (total: 191)
    # + 4 preparation_cap formula nodes (cleric, druid, paladin, wizard) + 1 paladin half_level mapping = 5 nodes (total: 196)
    assert map_size(system.nodes) == 242
    # topological_order returns false if cyclic, a list if acyclic
    assert is_list(Graph.topological_order(system))
  end
end
