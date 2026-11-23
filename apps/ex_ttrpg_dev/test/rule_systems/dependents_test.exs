defmodule ExTTRPGDev.RuleSystems.DependentsTest do
  # Not async: overrides the global :characters_path and
  # :rule_system_dependents application env (see characters/store_test.exs).
  use ExUnit.Case
  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.{Character, Metadata}
  alias ExTTRPGDev.RuleSystems.Dependents

  defmodule HostDependents do
    @behaviour ExTTRPGDev.RuleSystems.Dependents
    @impl true
    def dependents("sys", "1.0.0"), do: {:ok, [{:campaign, 7}]}
    def dependents(_, _), do: {:ok, []}
  end

  defmodule FailingDependents do
    @behaviour ExTTRPGDev.RuleSystems.Dependents
    @impl true
    def dependents(_, _), do: {:error, :db_down}
  end

  setup do
    tmp_dir =
      Path.join(
        System.tmp_dir!(),
        "ex_ttrpg_dev_dependents_#{System.unique_integer([:positive])}"
      )

    Application.put_env(:ex_ttrpg_dev, :characters_path, tmp_dir)

    on_exit(fn ->
      Application.delete_env(:ex_ttrpg_dev, :characters_path)
      Application.delete_env(:ex_ttrpg_dev, :rule_system_dependents)
      File.rm_rf(tmp_dir)
    end)

    :ok =
      Characters.save_character(%Character{
        name: "Hero",
        generated_values: %{},
        metadata: %Metadata{slug: "hero", rule_system: "sys", rule_system_version: "1.0.0"}
      })

    :ok
  end

  test "find/2 reports saved characters without any configuration" do
    assert Dependents.sources() == [Dependents]
    assert {:ok, [{Dependents, "hero"}]} = Dependents.find("sys", "1.0.0")
  end

  test "find/2 adds dependents from configured host modules" do
    Application.put_env(:ex_ttrpg_dev, :rule_system_dependents, [HostDependents])

    assert {:ok, [{Dependents, "hero"}, {HostDependents, {:campaign, 7}}]} =
             Dependents.find("sys", "1.0.0")

    assert {:ok, []} = Dependents.find("other", "1.0.0")
  end

  test "find/2 fails if any source fails" do
    Application.put_env(:ex_ttrpg_dev, :rule_system_dependents, [FailingDependents])
    assert {:error, {FailingDependents, :db_down}} = Dependents.find("sys", "1.0.0")
  end
end
