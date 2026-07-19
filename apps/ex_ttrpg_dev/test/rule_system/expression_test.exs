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

    test "returns error when expression raises at eval time" do
      # Formula has no refs, so substitution is a no-op, but it calls an undefined function
      assert {:error, {:eval_error, _, _}} =
               Expression.evaluate("undefined_function_xyz()", %{})
    end

    test "resolves refs sharing a prefix regardless of binding order" do
      bindings = %{
        {"attr", "strength", "mod"} => 100,
        {"attr", "strength", "modifier"} => 3
      }

      assert {:ok, 103} =
               Expression.evaluate("attr('strength').mod + attr('strength').modifier", bindings)

      assert {:ok, 103} =
               Expression.evaluate("attr('strength').modifier + attr('strength').mod", bindings)
    end

    test "supports unary minus on parenthesized expressions" do
      bindings = %{{"ability", "dexterity", "modifier"} => 4}

      assert {:ok, -2} =
               Expression.evaluate("-(max(0, ability('dexterity').modifier - 2))", bindings)
    end

    test "supports ceil and trunc" do
      assert {:ok, 3} = Expression.evaluate("ceil(5 / 2)", %{})
      assert {:ok, 2} = Expression.evaluate("trunc(5 / 2)", %{})
    end

    test "supports min and abs" do
      assert {:ok, 2} = Expression.evaluate("min(2, 5)", %{})
      assert {:ok, 3} = Expression.evaluate("abs(0 - 3)", %{})
    end

    test "division produces floats; floor converts to integer" do
      assert {:ok, 2.5} = Expression.evaluate("10 / 4", %{})
      assert {:ok, 2} = Expression.evaluate("floor(10 / 4)", %{})
    end

    test "division by zero returns an error instead of raising" do
      assert {:error, {:eval_error, message, _}} = Expression.evaluate("1 / 0", %{})
      assert message =~ "division by zero"
    end

    test "evaluates boolean literals" do
      assert {:ok, true} = Expression.evaluate("true", %{})
      assert {:ok, false} = Expression.evaluate("false", %{})
    end

    test "evaluates comparisons and boolean logic" do
      assert {:ok, false} = Expression.evaluate("1 > 2", %{})
      assert {:ok, true} = Expression.evaluate("2 >= 2 and not false", %{})
      assert {:ok, true} = Expression.evaluate("1 == 2 or 3 != 4", %{})
    end

    test "comparison against a ref value" do
      bindings = %{{"character_trait", "character_level", "level"} => 5}

      assert {:ok, true} =
               Expression.evaluate("character_trait('character_level').level >= 5", bindings)
    end

    test "rejects module calls and atoms at parse time" do
      assert {:error, {:parse_error, _, _}} =
               Expression.evaluate(~s|System.cmd("rm", ["-rf", "/"])|, %{})

      assert {:error, {:parse_error, _, _}} = Expression.evaluate(":os.cmd('id')", %{})
      assert {:error, {:parse_error, _, _}} = Expression.evaluate("IO.puts(1)", %{})
    end

    test "rejects non-whitelisted functions at eval time" do
      assert {:error, {:eval_error, message, _}} = Expression.evaluate("self()", %{})
      assert message =~ "unknown function"
    end

    test "rejects bare identifiers" do
      assert {:error, {:parse_error, _, _}} = Expression.evaluate("strength", %{})
    end

    test "rejects malformed syntax" do
      assert {:error, {:parse_error, _, _}} = Expression.evaluate("1 + ", %{})
      assert {:error, {:parse_error, _, _}} = Expression.evaluate("1 2", %{})
      assert {:error, {:parse_error, _, _}} = Expression.evaluate("(1 + 2", %{})
    end

    test "arithmetic on booleans returns an error" do
      assert {:error, {:eval_error, _, _}} = Expression.evaluate("true + 1", %{})
    end
  end

  describe "parse/1" do
    test "parses a valid formula" do
      assert {:ok, _ast} = Expression.parse("floor((attr('dexterity').total_score - 10) / 2)")
    end

    test "returns a parse error for invalid syntax" do
      assert {:error, {:parse_error, _}} = Expression.parse("1 +")
    end
  end
end
