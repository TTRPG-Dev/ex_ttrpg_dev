defmodule ExRPGTest do
  use ExUnit.Case
  doctest ExRPG

  test "greets the world" do
    assert ExRPG.hello() == :world
  end
end
