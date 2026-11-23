defmodule ExTTRPGDev.RuleSystem.VersioningTest do
  use ExUnit.Case, async: true
  alias ExTTRPGDev.RuleSystem.{RuleModule, Versioning}

  doctest ExTTRPGDev.RuleSystem.Versioning

  test "library_compatible?/1 defaults to the running library version" do
    running = Versioning.library_version()
    assert Versioning.library_compatible?(%RuleModule{library_requirement: "== #{running}"})
    refute Versioning.library_compatible?(%RuleModule{library_requirement: "> #{running}"})
  end

  test "breaking_change?/2 treats 0.x -> 1.0 as breaking" do
    assert Versioning.breaking_change?("0.9.0", "1.0.0")
  end

  test "breaking_change?/2 ignores patch and pre-release differences" do
    refute Versioning.breaking_change?("1.0.0", "1.0.1")
    refute Versioning.breaking_change?("1.0.0-rc.1", "1.0.0")
  end
end
