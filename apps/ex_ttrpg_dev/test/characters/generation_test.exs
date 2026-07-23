defmodule ExTTRPGDevTest.Characters.Generation do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.RuleSystems

  describe "random_decisions/1" do
    setup do
      {:ok, system: RuleSystems.load_system!("dnd_5e_srd")}
    end

    test "returns one root decision per character choice", %{system: system} do
      decisions = Characters.random_decisions(system)
      root = Enum.filter(decisions, &(&1.scope == nil))
      assert length(root) == length(system.module.character_building_choices)
    end

    test "root decision choice matches the character_choice concept_type", %{system: system} do
      decisions = Characters.random_decisions(system)

      for %{concept_type: type_id} <- system.module.character_building_choices do
        assert Enum.any?(decisions, &(&1.scope == nil and &1.choice == type_id))
      end
    end

    test "selected root race is not a subrace", %{system: system} do
      decisions = Characters.random_decisions(system)
      root_race = Enum.find(decisions, &(&1.scope == nil and &1.choice == "race"))

      subraces = ~w[hill_dwarf high_elf lightfoot_halfling rock_gnome]

      refute root_race.selection in subraces
    end

    test "equipment choices (grants_to: inventory) produce a decision but do not recurse", %{
      system: system
    } do
      concept_metadata =
        Map.put(system.concept_metadata, {"class", "fighter"}, %{
          "choices" => %{
            "starting_weapon" => %{
              "type" => "equipment",
              "grants_to" => "inventory",
              "options" => ["longsword", "shortsword"]
            }
          }
        })

      system = %{system | concept_metadata: concept_metadata}

      for _ <- 1..10 do
        decisions = Characters.random_decisions(system)

        weapon_decision =
          Enum.find(decisions, fn d ->
            d.scope != nil and elem(d.scope, 0) == "class" and d.choice == "starting_weapon"
          end)

        if weapon_decision do
          assert weapon_decision.selection in ["longsword", "shortsword"]
          # The selected equipment id should not appear as a scope in any decision
          refute Enum.any?(decisions, fn d ->
                   d.scope != nil and elem(d.scope, 1) == weapon_decision.selection
                 end)
        end
      end
    end

    test "races with subraces produce a subrace decision", %{system: system} do
      races_with_subraces = ~w[dwarf elf halfling gnome]

      for _ <- 1..20 do
        decisions = Characters.random_decisions(system)
        root_race = Enum.find(decisions, &(&1.scope == nil and &1.choice == "race"))

        if root_race.selection in races_with_subraces do
          parent_scope = {"race", root_race.selection}
          assert Enum.any?(decisions, &(&1.scope == parent_scope and &1.choice == "subrace"))
        end
      end
    end
  end
end
