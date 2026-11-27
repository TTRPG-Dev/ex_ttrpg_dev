defmodule ExTTRPGDev.RuleSystem.DiceTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.Dice

  doctest Dice

  describe "new/2" do
    test "allows zero dice" do
      assert {:ok, %Dice{terms: [{0, 6}]}} = Dice.new(0, 6)
    end

    test "rejects non-integer, negative or zero-sided dice" do
      assert {:error, _} = Dice.new(-1, 6)
      assert {:error, _} = Dice.new(1, 0)
      assert {:error, _} = Dice.new(1, 6.0)
      assert {:error, _} = Dice.new(true, 6)
    end
  end

  describe "parse/1 and to_string/1" do
    test "round-trip standard notation" do
      for notation <- ~w[1d20 2d6+3 1d8-1 5d4*10 1d4*10+10 0d6 2d6+1d8+3 (1d4+1d6)*10-2] do
        assert notation |> Dice.parse!() |> to_string() == notation
      end
    end

    test "merges and orders terms into canonical form" do
      assert to_string(Dice.parse!("1d8+1d6+1d6")) == "2d6+1d8"
      assert to_string(Dice.parse!("0d6+1d8")) == "1d8"
    end

    test "rejects malformed notation" do
      for notation <- [
            "",
            "3",
            "d",
            "2d",
            "2d6+",
            "2d6*0",
            "2d6 + 3",
            "2D6",
            "1d0",
            "+1d6",
            "1d6++1d8",
            "1d4+1d6*10",
            "(1d4+1d6)",
            "(1d4+1d6*10)"
          ] do
        assert {:error, _} = Dice.parse(notation), "expected #{inspect(notation)} to be rejected"
      end

      assert {:error, _} = Dice.parse(6)
    end

    test "parse!/1 raises on malformed notation" do
      assert_raise ArgumentError, ~r/invalid dice notation/, fn -> Dice.parse!("2d") end
    end
  end

  describe "add/2" do
    test "subtracting is adding a negative modifier" do
      assert {:ok, %Dice{modifier: -2}} = Dice.add(Dice.parse!("1d6"), -2)
    end

    test "is commutative with integers" do
      assert Dice.add(3, Dice.parse!("1d6")) == Dice.add(Dice.parse!("1d6"), 3)
    end

    test "pools dice of different sizes" do
      {:ok, pool} = Dice.add(Dice.parse!("2d6+3"), Dice.parse!("1d8"))
      assert to_string(pool) == "2d6+1d8+3"

      {:ok, pool} = Dice.add(pool, Dice.parse!("1d6+1d4"))
      assert to_string(pool) == "1d4+3d6+1d8+3"
    end

    test "zero-count terms drop out of a pool with other dice" do
      assert {:ok, %Dice{terms: [{1, 8}]}} = Dice.add(Dice.parse!("0d6"), Dice.parse!("1d8"))
      assert {:ok, %Dice{terms: [{0, 6}]}} = Dice.add(Dice.parse!("0d6"), Dice.parse!("0d6"))
    end

    test "requires the same multiplier to sum dice" do
      assert {:error, _} = Dice.add(Dice.parse!("1d6*10"), Dice.parse!("1d6"))
    end

    test "rejects non-integer offsets" do
      assert {:error, _} = Dice.add(Dice.parse!("1d6"), 1.5)
      assert {:error, _} = Dice.add(Dice.parse!("1d6"), true)
    end
  end

  describe "multiply/2" do
    test "is commutative and compounds" do
      {:ok, once} = Dice.multiply(10, Dice.parse!("5d4"))
      assert {:ok, %Dice{multiplier: 20}} = Dice.multiply(once, 2)
    end

    test "rejects zero, negative and non-integer factors" do
      for factor <- [0, -1, 1.5] do
        assert {:error, _} = Dice.multiply(Dice.parse!("1d6"), factor)
      end
    end
  end

  describe "roll/1" do
    test "applies multiplier before modifier" do
      %{rolls: [die], total: total} = Dice.roll("1d1*10+3")
      assert die == 1
      assert total == 13
    end

    test "rolls every term of a pool, grouped by term" do
      %{rolls: rolls, rolls_by_term: [d4s, d6s], total: total} = Dice.roll("2d4+1d6+1")

      assert %{dice: "2d4", rolls: [_, _]} = d4s
      assert %{dice: "1d6", rolls: [_]} = d6s
      assert rolls == d4s.rolls ++ d6s.rolls
      assert total == Enum.sum(rolls) + 1
    end

    test "multiplies a pool's whole rolled total" do
      assert %{rolls: [1, 1], total: 23} = Dice.roll("(1d1+1d1)*10+3")
    end

    test "totals stay within the dice's range" do
      for _ <- 1..50 do
        %{rolls: rolls, total: total} = Dice.roll(Dice.parse!("3d6+1"))
        assert length(rolls) == 3
        assert total in 4..19
      end
    end
  end

  test "encodes to JSON as notation" do
    assert Jason.encode!(%{dice: Dice.parse!("2d6+3")}) == ~s({"dice":"2d6+3"})
  end
end
