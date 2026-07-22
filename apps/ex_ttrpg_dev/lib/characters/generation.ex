defmodule ExTTRPGDev.Characters.Generation do
  @moduledoc """
  Random decision generation for character building: picking a random root
  concept for each of the system's character-building choices and recursing
  into the sub-choices each selection declares.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.random_decisions/1`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters.Decision
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Generates a random decision list for a system.

  See `ExTTRPGDev.Characters.random_decisions/1` for documentation.
  """
  def random_decisions(%LoadedSystem{} = system) do
    system.module.character_building_choices
    |> Enum.flat_map(fn %{concept_type: type_id} ->
      root_ids = root_concept_ids(system.concept_metadata, type_id)
      selected_id = Enum.random(root_ids)
      decision = %Decision{scope: nil, choice: type_id, selection: selected_id}
      [decision | random_sub_decisions(system.concept_metadata, {type_id, selected_id})]
    end)
  end

  @doc """
  Returns the IDs of root (non-sub) concepts of `type_id` from `concept_metadata`.

  See `ExTTRPGDev.Characters.root_concept_ids/2` for documentation.
  """
  def root_concept_ids(concept_metadata, type_id) do
    all_ids =
      concept_metadata
      |> Enum.filter(fn {{t, _}, _} -> t == type_id end)
      |> Enum.map(fn {{_, id}, _} -> id end)

    sub_ids =
      concept_metadata
      |> Enum.flat_map(fn {_, meta} -> sub_option_ids(meta, type_id) end)
      |> MapSet.new()

    Enum.reject(all_ids, &MapSet.member?(sub_ids, &1))
  end

  defp random_sub_decisions(concept_metadata, {type_id, concept_id} = key) do
    concept_metadata
    |> Map.get(key, %{})
    |> Map.get("choices", %{})
    |> Enum.flat_map(fn {choice_id, choice_def} ->
      sub_type = choice_def["type"]
      selected = Enum.random(choice_def["options"])
      decision = %Decision{scope: {type_id, concept_id}, choice: choice_id, selection: selected}

      if Map.get(choice_def, "grants_to") == "inventory" do
        [decision]
      else
        [decision | random_sub_decisions(concept_metadata, {sub_type, selected})]
      end
    end)
  end

  defp sub_option_ids(meta, type_id) do
    meta
    |> Map.get("choices", %{})
    |> Enum.flat_map(fn {_, choice_def} ->
      if choice_def["type"] == type_id, do: choice_def["options"] || [], else: []
    end)
  end
end
