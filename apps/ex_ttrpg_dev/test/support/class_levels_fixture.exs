defmodule ExTTRPGDevTest.ClassLevelsFixture do
  @moduledoc false
  # Loads test/fixtures/class_levels, a minimal system with class levels
  # enabled, and builds characters for it.

  alias ExTTRPGDev.Characters.{Character, Decision, Metadata}
  alias ExTTRPGDev.RuleSystem.{Effect, Graph, Loader}
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  def path, do: Path.expand("../fixtures/class_levels", __DIR__)

  def system!, do: build_system!(Loader.load!(path()))

  # Copies the fixture to a temp dir, lets `modify` change its files, and
  # loads that copy. Returns what Loader.load/1 does.
  def load_modified(modify) do
    dir =
      Path.join(System.tmp_dir!(), "ex_ttrpg_class_levels_#{System.unique_integer([:positive])}")

    File.cp_r!(path(), dir)

    try do
      modify.(dir)
      Loader.load(dir)
    after
      File.rm_rf!(dir)
    end
  end

  # Replaces `from` with `to` in the fixture file at `relative_path`.
  def replace_in(dir, relative_path, from, to) do
    file = Path.join(dir, relative_path)
    content = File.read!(file)

    unless String.contains?(content, from),
      do: raise("#{relative_path} doesn't contain #{inspect(from)}")

    File.write!(file, String.replace(content, from, to))
  end

  def build_system!(data) do
    {:ok, built} = Graph.build(data)

    %LoadedSystem{
      module: data.module,
      graph: built.graph,
      nodes: built.nodes,
      rolling_methods: data.rolling_methods,
      concept_metadata: data.concept_metadata,
      effects: data.effects,
      inventory_rules: data.inventory_rules
    }
  end

  # A character whose first class is `class_id`, with `xp` experience
  # points and the given level record.
  def character(class_id, opts \\ []) do
    xp = Keyword.get(opts, :xp, 0)
    scores = Keyword.get(opts, :scores, %{})

    %Character{
      name: "Test",
      generated_values: %{
        {"ability", "strength", "score"} => Map.get(scores, "strength", 10),
        {"ability", "intelligence", "score"} => Map.get(scores, "intelligence", 10)
      },
      effects: xp_effects(xp),
      decisions:
        [%Decision{scope: nil, choice: "class", selection: class_id}] ++
          Keyword.get(opts, :decisions, []),
      level_classes: Keyword.get(opts, :level_classes, []),
      metadata: %Metadata{slug: "test", rule_system: "class_levels_test"}
    }
  end

  defp xp_effects(0), do: []

  defp xp_effects(xp),
    do: [%Effect{target: {"character_trait", "experience_points", "total"}, value: xp}]
end
