defmodule ExTTRPGDev.RuleSystems.BundledTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.Source
  alias ExTTRPGDev.RuleSystems.Bundled

  doctest ExTTRPGDev.RuleSystems.Bundled

  test "fetch/1 reads a bundled system's content" do
    assert {:ok, %Source{module: %{"module" => %{"slug" => "dnd_5e_srd"}}}} =
             Bundled.fetch("dnd_5e_srd")
  end

  test "fetch/1 returns :not_found for a slug that isn't bundled" do
    assert {:error, :not_found} = Bundled.fetch("not_bundled")
  end
end
