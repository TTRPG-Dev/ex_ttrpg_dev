defmodule ExTTRPGDev.RuleSystems.ReplacementTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog
  alias ExTTRPGDev.RuleSystem.RuleModule
  alias ExTTRPGDev.RuleSystems.Replacement

  defp canonical(version, requirement \\ "~> 0.15.0") do
    %RuleModule{slug: "sys", version: version, library_requirement: requirement}
  end

  defp decide(installed, release, dependents \\ %{}) do
    Replacement.decide(installed, release,
      library_version: "0.15.1",
      dependents: fn "sys", version -> {:ok, Map.get(dependents, version, [])} end
    )
  end

  describe "exemptions" do
    test "never applies non-canonical content" do
      assert {:skip, :not_canonical} = decide([], %RuleModule{slug: "sys", version: "1.0.0"})
    end

    test "keeps a non-canonical system that holds the slug" do
      local = %RuleModule{slug: "sys", version: "homebrew"}
      assert {:skip, {:slug_taken, "homebrew"}} = decide([local], canonical("1.0.0"))
    end
  end

  describe "hard gate" do
    test "blocks a release the running library doesn't satisfy, before anything else" do
      assert {:blocked, {:library_requirement, "~> 1.4", "0.15.1"}} =
               decide([], canonical("1.0.0", "~> 1.4"))
    end
  end

  describe "soft gate" do
    test "installs when nothing is installed" do
      assert {:apply, %{install: "1.0.0", remove: [], retain: []}} =
               decide([], canonical("1.0.0"))
    end

    test "replaces in place on a non-breaking bump, even with dependents" do
      assert {:apply, %{install: "1.1.0", remove: ["1.0.0"], retain: []}} =
               decide([canonical("1.0.0")], canonical("1.1.0"), %{"1.0.0" => [:hero]})
    end

    test "replaces a breaking bump's predecessor when nothing depends on it" do
      assert {:apply, %{install: "2.0.0", remove: ["1.1.0"], retain: []}} =
               decide([canonical("1.1.0")], canonical("2.0.0"))
    end

    test "installs a breaking bump alongside versions with dependents" do
      installed = [canonical("1.1.0"), canonical("2.3.0")]

      assert {:apply, %{install: "3.0.0", remove: ["2.3.0"], retain: [{"1.1.0", [:hero]}]}} =
               decide(installed, canonical("3.0.0"), %{"1.1.0" => [:hero]})
    end

    test "updates an older retained line in place" do
      installed = [canonical("1.1.0"), canonical("2.0.0")]

      assert {:apply, %{install: "1.2.0", remove: ["1.1.0"], retain: []}} =
               decide(installed, canonical("1.2.0"))
    end

    test "treats pre-1.0 minor bumps as breaking" do
      assert {:apply, %{install: "0.3.0", retain: [{"0.2.0", [:hero]}]}} =
               decide([canonical("0.2.0")], canonical("0.3.0"), %{"0.2.0" => [:hero]})
    end

    test "skips a release that is already installed" do
      assert {:skip, {:already_installed, "1.0.0"}} =
               decide([canonical("1.0.0")], canonical("1.0.0"))
    end

    test "skips a release older than the installed version on its line" do
      assert {:skip, {:superseded_by, "1.2.0"}} = decide([canonical("1.2.0")], canonical("1.1.0"))
    end

    test "skips a release older than everything installed with no line of its own" do
      assert {:skip, {:superseded_by, "2.0.0"}} = decide([canonical("2.0.0")], canonical("1.0.0"))
    end

    test "fails closed when dependents can't be determined" do
      assert {:error, {:dependents, "1.0.0", :db_down}} =
               Replacement.decide([canonical("1.0.0")], canonical("2.0.0"),
                 library_version: "0.15.1",
                 dependents: fn _, _ -> {:error, :db_down} end
               )
    end
  end

  test "decide/3 defaults to the running library and the configured dependents" do
    release = canonical("1.0.0", "== #{ExTTRPGDev.RuleSystem.Versioning.library_version()}")
    assert {:apply, %{install: "1.0.0"}} = Replacement.decide([], release)
  end

  describe "log/2" do
    test "logs a clean apply at info and returns the decision" do
      decision = decide([canonical("1.0.0")], canonical("1.1.0"))

      log =
        capture_log([level: :info], fn ->
          assert Replacement.log(decision, canonical("1.1.0")) == decision
        end)

      assert log =~ ~s("sys" 1.1.0: applying, replacing 1.0.0)
    end

    test "logs no-op decisions at debug" do
      release = canonical("1.0.0")
      decision = decide([canonical("1.0.0")], release)

      assert capture_log([level: :info], fn -> Replacement.log(decision, release) end) == ""

      assert capture_log([level: :debug], fn -> Replacement.log(decision, release) end) =~
               "already installed"
    end

    test "warns about retained versions" do
      release = canonical("2.0.0")
      decision = decide([canonical("1.0.0")], release, %{"1.0.0" => [:a, :b]})

      log = capture_log(fn -> Replacement.log(decision, release) end)
      assert log =~ "[warning]"
      assert log =~ "1.0.0 retained for 2 dependent(s); manual migration required"
    end

    test "warns when the hard gate blocks" do
      release = canonical("1.0.0", "~> 1.4")
      log = capture_log(fn -> Replacement.log(decide([], release), release) end)
      assert log =~ ~s(library_requirement "~> 1.4" NOT satisfied by running 0.15.1)
    end

    test "logs an error when dependents are unknown" do
      log = capture_log(fn -> Replacement.log({:error, :boom}, canonical("1.0.0")) end)
      assert log =~ "[error]"
      assert log =~ "could not determine dependents"
    end
  end
end
