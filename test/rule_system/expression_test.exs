defmodule ExTTRPGDev.RuleSystem.ExpressionTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.Expression

  describe "extract_refs/1" do
    test "extracts a single ref from a modifier formula" do
      refs = Expression.extract_refs("floor((attr('dexterity').total_score - 10) / 2)")
      assert refs == [{"attr", "dexterity", "total_score"}]
    end

    test "extracts a single ref from a simple reference" do
      refs = Expression.extract_refs("attr('strength').modifier")
      assert refs == [{"attr", "strength", "modifier"}]
    end

    test "extracts multiple different refs" do
      formula = "attr('strength').modifier + skill('athletics').bonus"
      refs = Expression.extract_refs(formula)
      assert {"attr", "strength", "modifier"} in refs
      assert {"skill", "athletics", "bonus"} in refs
    end

    test "deduplicates repeated refs" do
      formula = "attr('dexterity').modifier + attr('dexterity').modifier"
      refs = Expression.extract_refs(formula)
      assert refs == [{"attr", "dexterity", "modifier"}]
    end

    test "returns empty list for formula with no refs" do
      assert Expression.extract_refs("42") == []
      assert Expression.extract_refs("floor(10 / 2)") == []
    end
  end

  describe "evaluate/2" do
    test "evaluates D&D modifier formula correctly for score 18" do
      bindings = %{{"attr", "dexterity", "total_score"} => 18}

      assert {:ok, 4} =
               Expression.evaluate("floor((attr('dexterity').total_score - 10) / 2)", bindings)
    end

    test "evaluates D&D modifier formula with odd score (floors correctly)" do
      bindings = %{{"attr", "dexterity", "total_score"} => 15}

      assert {:ok, 2} =
               Expression.evaluate("floor((attr('dexterity').total_score - 10) / 2)", bindings)
    end

    test "evaluates D&D modifier formula with score below 10 (negative modifier)" do
      bindings = %{{"attr", "dexterity", "total_score"} => 8}

      assert {:ok, -1} =
               Expression.evaluate("floor((attr('dexterity').total_score - 10) / 2)", bindings)
    end

    test "evaluates a simple reference formula" do
      bindings = %{{"attr", "strength", "base_score"} => 14}
      assert {:ok, 14} = Expression.evaluate("attr('strength').base_score", bindings)
    end

    test "evaluates formula with multiple refs" do
      bindings = %{
        {"attr", "strength", "modifier"} => 2,
        {"skill", "athletics", "bonus"} => 3
      }

      assert {:ok, 5} =
               Expression.evaluate(
                 "attr('strength').modifier + skill('athletics').bonus",
                 bindings
               )
    end

    test "returns error on unresolvable formula" do
      assert {:error, _} = Expression.evaluate("attr('dexterity').total_score", %{})
    end
  end
end
