defmodule ExTTRPGDev.Characters.Leveling do
  @moduledoc """
  XP and level math: mapping the system's level node to XP thresholds,
  computing the XP needed for the next level, and evaluating the DAG as it
  would resolve at a given level.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.xp_to_next_level/2`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystem.Evaluator
  alias ExTTRPGDev.RuleSystem.Expression
  alias ExTTRPGDev.RuleSystem.Node
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Returns the XP needed for a character to reach the next level in the given system.

  See `ExTTRPGDev.Characters.xp_to_next_level/2` for documentation.
  """
  def xp_to_next_level(%LoadedSystem{} = system, %Character{} = character) do
    thresholds = level_xp_thresholds(system)

    if map_size(thresholds) == 0 do
      {:error, :no_level_thresholds}
    else
      xp_target = xp_effect_target(system)

      current_xp =
        character.effects
        |> Enum.filter(&(&1.target == xp_target))
        |> Enum.map(& &1.value)
        |> Enum.sum()

      current_level =
        thresholds
        |> Enum.filter(fn {_level, threshold} -> threshold <= current_xp end)
        |> Enum.max_by(fn {_level, threshold} -> threshold end, fn -> nil end)
        |> case do
          nil -> 1
          {level, _} -> level
        end

      next_level =
        thresholds
        |> Map.keys()
        |> Enum.sort()
        |> Enum.find(&(&1 > current_level))

      if is_nil(next_level) do
        {:error, :max_level}
      else
        {:ok, Map.fetch!(thresholds, next_level) - current_xp, next_level}
      end
    end
  end

  # The `%{level => xp_threshold}` map derived from the system's level node,
  # or `%{}` when the system defines no level mapping.
  @doc false
  def level_xp_thresholds(%LoadedSystem{} = system) do
    with level_node when not is_nil(level_node) <- system.module.level_node,
         [{type_id, concept_id, field_name} | _] <- Expression.extract_refs(level_node),
         %Node{type: :mapping, steps: steps} when not is_nil(steps) <-
           Map.get(system.nodes, {type_id, concept_id, field_name}) do
      Map.new(steps, fn [threshold, level] -> {level, threshold} end)
    else
      _ -> %{}
    end
  end

  # The node key XP effects contribute to (the level mapping's input node),
  # or `nil` when the system defines no level mapping.
  @doc false
  def xp_effect_target(%LoadedSystem{} = system) do
    with level_node when not is_nil(level_node) <- system.module.level_node,
         [{type_id, concept_id, field_name} | _] <- Expression.extract_refs(level_node),
         %Node{type: :mapping, input: input} when not is_nil(input) <-
           Map.get(system.nodes, {type_id, concept_id, field_name}),
         [node_key | _] <- Expression.extract_refs(input) do
      node_key
    else
      _ -> nil
    end
  end

  # Evaluates the DAG as it would resolve at `level`: the character's XP
  # effects are replaced by exactly the XP required for that level.
  @doc false
  def evaluate_at_level(
        %LoadedSystem{} = system,
        %Character{} = character,
        level,
        thresholds,
        xp_target,
        all_effects
      ) do
    xp_for_level = Map.get(thresholds, level, 0)
    non_xp_effects = Enum.reject(all_effects, &(&1.target == xp_target))

    level_effects =
      if xp_target && xp_for_level > 0 do
        [%Effect{target: xp_target, value: xp_for_level} | non_xp_effects]
      else
        non_xp_effects
      end

    Evaluator.evaluate!(system, character.generated_values, level_effects)
  end
end
