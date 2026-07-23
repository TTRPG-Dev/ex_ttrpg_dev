defmodule ExTTRPGDev.Characters.Effects do
  @moduledoc """
  Effect aggregation for characters: deriving the active concept set from a
  character's decisions, collecting the effects those concepts (plus
  inventory and the character's own effects) contribute, and evaluating the
  system DAG against them.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.resolved_state/2`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Decision
  alias ExTTRPGDev.Characters.InventoryItem
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystem.Evaluator
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Returns the set of active `{type_id, concept_id}` pairs derived from a character's decisions.

  See `ExTTRPGDev.Characters.active_concepts/2` for documentation.
  """
  def active_concepts(decisions, concept_metadata) do
    decisions
    |> Enum.filter(fn d -> d.scope == nil end)
    |> Enum.reduce(MapSet.new(), fn %{choice: type, selection: id}, acc ->
      collect_active_concepts({type, id}, decisions, concept_metadata, acc)
    end)
  end

  @doc """
  Returns the combined effects list for a character against a system.

  See `ExTTRPGDev.Characters.active_effects/2` for documentation.
  """
  def active_effects(%LoadedSystem{} = system, %Character{} = character) do
    active = active_concepts(character.decisions, system.concept_metadata)
    decision_effects = effects_from_decisions(character.decisions, system.concept_metadata)

    system.effects
    |> Enum.filter(fn
      %Effect{source: {type, id}} -> MapSet.member?(active, {type, id})
      %Effect{source: {type, id, _}} -> MapSet.member?(active, {type, id})
      _ -> false
    end)
    |> Kernel.++(decision_effects)
    |> Kernel.++(inventory_effects(system, character.inventory))
    |> Kernel.++(character.effects)
  end

  @doc """
  Computes the character's active effects and evaluates the full system DAG against them.

  See `ExTTRPGDev.Characters.resolved_state/2` for documentation.
  """
  def resolved_state(%LoadedSystem{} = system, %Character{} = character) do
    effects = active_effects(system, character)
    {effects, Evaluator.evaluate!(system, character.generated_values, effects)}
  end

  defp collect_active_concepts({_type, _id} = key, decisions, concept_metadata, acc) do
    acc = MapSet.put(acc, key)
    choices = concept_metadata |> Map.get(key, %{}) |> Map.get("choices", %{})

    Enum.reduce(choices, acc, fn {choice_id, choice_def}, acc ->
      decision = Enum.find(decisions, &(&1.scope == key and &1.choice == choice_id))

      if decision && choice_def["grants_to"] != "inventory" do
        collect_active_concepts(
          {choice_def["type"], decision.selection},
          decisions,
          concept_metadata,
          acc
        )
      else
        acc
      end
    end)
  end

  defp effects_from_decisions(decisions, concept_metadata) do
    Enum.flat_map(decisions, fn
      %Decision{scope: {type, id}, choice: choice_id, selection: selected} ->
        choice_def =
          concept_metadata
          |> Map.get({type, id}, %{})
          |> Map.get("choices", %{})
          |> Map.get(choice_id, %{})

        case choice_def do
          %{
            "contributes_field" => field,
            "contributes_value" => value,
            "type" => target_type
          } ->
            [%Effect{source: {type, id}, target: {target_type, selected, field}, value: value}]

          _ ->
            []
        end

      _ ->
        []
    end)
  end

  defp inventory_effects(%LoadedSystem{} = system, inventory) do
    Enum.flat_map(inventory, fn %InventoryItem{} = item ->
      system.effects
      |> Enum.filter(fn
        %Effect{source: {type, id}} -> type == item.concept_type and id == item.concept_id
        _ -> false
      end)
      |> Enum.map(fn %Effect{} = effect -> %{effect | item_fields: item.fields} end)
    end)
  end
end
