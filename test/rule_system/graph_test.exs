defmodule ExTTRPGDev.RuleSystem.GraphTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.{Graph, Loader}

  defp minimal_loader_data do
    %{
      nodes: %{
        {"attr", "strength", "base_score"} => %{type: :generated, method: "standard"},
        {"attr", "strength", "total_score"} => %{
          type: :accumulator,
          base: "attr('strength').base_score"
        },
        {"attr", "strength", "modifier"} => %{
          type: :formula,
          formula: "floor((attr('strength').total_score - 10) / 2)"
        }
      },
      rolling_methods: %{},
      concept_metadata: %{},
      effects: []
    }
  end

  defp dnd_path do
    Application.app_dir(:ex_ttrpg_dev, "priv/system_configs/dnd_5e_srd")
  end

  test "build/1 succeeds on valid minimal data" do
    assert {:ok, system} = Graph.build(minimal_loader_data())
    assert is_map(system.graph)
    assert map_size(system.nodes) == 3
  end

  test "build/1 returns error for undefined reference" do
    bad_data = %{
      nodes: %{
        {"attr", "strength", "modifier"} => %{
          type: :formula,
          formula: "attr('strength').total_score"
        }
      },
      rolling_methods: %{},
      concept_metadata: %{},
      effects: []
    }

    assert {:error, {:undefined_ref, _}} = Graph.build(bad_data)
  end

  test "build/1 detects cycles" do
    cyclic_data = %{
      nodes: %{
        {"attr", "a", "val"} => %{type: :formula, formula: "attr('b').val"},
        {"attr", "b", "val"} => %{type: :formula, formula: "attr('a').val"}
      },
      rolling_methods: %{},
      concept_metadata: %{},
      effects: []
    }

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

  test "build/1 returns error for undefined contribution target" do
    data = %{
      nodes: %{
        {"attr", "strength", "base_score"} => %{type: :generated, method: "standard"}
      },
      rolling_methods: %{},
      concept_metadata: %{},
      effects: [
        %{source: {"item", "ring", nil}, target: {"attr", "strength", "nonexistent"}, value: 2}
      ]
    }

    assert {:error, {:undefined_effect_target, _}} = Graph.build(data)
  end

  test "integration: build succeeds for full dnd_5e_srd" do
    {:ok, loader_data} = Loader.load(dnd_path())
    assert {:ok, system} = Graph.build(loader_data)

    # 6 attrs * 3 fields + 18 skills * 1 field = 36 nodes
    assert map_size(system.nodes) == 36
    # topological_order returns false if cyclic, a list if acyclic
    assert is_list(Graph.topological_order(system))
  end
end
