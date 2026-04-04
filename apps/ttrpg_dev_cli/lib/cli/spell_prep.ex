defmodule ExTTRPGDev.CLI.SpellPrep do
  @moduledoc """
  Helper functions for the `characters.spells` and `characters.prepare` server commands.

  Extracted from `Server` to keep that module within size thresholds.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Returns a map describing the character's current spell preparation state.

  For "prepared" mode classes the map includes:
    - `:preparation_mode` — `"prepared"`
    - `:cap` — maximum spells preparable
    - `:eligible_spells` — IDs available for preparation
    - `:prepared_spells` — IDs currently prepared
    - `:always_prepared` — IDs always prepared from subclass

  For "all" mode classes `:prepared_spells` mirrors `:eligible_spells` and
  no `:cap` is included.

  Returns `%{preparation_mode: nil}` when the character's class does not
  declare a `preparation_mode`.
  """
  def query(%LoadedSystem{} = system, %Character{} = character) do
    case find_preparation_class(character, system) do
      nil -> %{preparation_mode: nil}
      class_key -> build_spells_response(system, character, class_key)
    end
  end

  defp build_spells_response(system, character, class_key) do
    mode = get_in(system.concept_metadata, [class_key, "preparation_mode"])
    always = Characters.always_prepared_spells(system, character, class_key)
    eligible = Characters.eligible_preparation_spells(system, character, class_key)

    case Characters.preparation_cap(system, character, class_key) do
      {:ok, cap} ->
        %{
          preparation_mode: mode,
          cap: cap,
          eligible_spells: eligible,
          prepared_spells: character.prepared_spells,
          always_prepared: always
        }

      {:error, :no_preparation_cap} ->
        %{
          preparation_mode: mode,
          eligible_spells: eligible,
          prepared_spells: eligible,
          always_prepared: always
        }
    end
  end

  @doc """
  Validates `spell_ids` against the eligible pool and preparation cap, then
  writes the updated `prepared_spells` to disk.

  Returns `{:ok, map}` with `:prepared_spells`, `:always_prepared`, and `:cap`
  on success, or `{:error, reason_string}` on validation failure.
  """
  def prepare(%LoadedSystem{} = system, %Character{} = character, spell_ids) do
    with {:ok, class_key} <- require_preparation_class(character, system),
         :ok <- require_prepared_mode(system, class_key),
         {:ok, cap} <- Characters.preparation_cap(system, character, class_key),
         eligible = Characters.eligible_preparation_spells(system, character, class_key),
         :ok <- validate_eligible(spell_ids, eligible),
         :ok <- validate_cap(spell_ids, cap) do
      updated = %{character | prepared_spells: Enum.sort(spell_ids)}
      Characters.save_character!(updated, true)
      always = Characters.always_prepared_spells(system, updated, class_key)
      {:ok, %{prepared_spells: updated.prepared_spells, always_prepared: always, cap: cap}}
    end
  end

  defp require_preparation_class(character, system) do
    case find_preparation_class(character, system) do
      nil -> {:error, "no class with preparation_mode found for this character"}
      key -> {:ok, key}
    end
  end

  defp require_prepared_mode(system, class_key) do
    mode = get_in(system.concept_metadata, [class_key, "preparation_mode"])

    if mode == "prepared",
      do: :ok,
      else: {:error, "spells for this class are not manually prepared"}
  end

  defp validate_eligible(spell_ids, eligible) do
    eligible_set = MapSet.new(eligible)
    invalid = Enum.reject(spell_ids, &MapSet.member?(eligible_set, &1))

    if Enum.empty?(invalid),
      do: :ok,
      else: {:error, "ineligible spells: #{Enum.join(invalid, ", ")}"}
  end

  defp validate_cap(spell_ids, cap) do
    if length(spell_ids) <= cap,
      do: :ok,
      else: {:error, "cannot prepare more than #{cap} spells (given: #{length(spell_ids)})"}
  end

  defp find_preparation_class(character, system) do
    Enum.find_value(system.module.character_building_choices, fn %{concept_type: type_id} ->
      find_prepared_concept(character.decisions, system.concept_metadata, type_id)
    end)
  end

  defp find_prepared_concept(decisions, concept_metadata, type_id) do
    Enum.find_value(decisions, fn
      %{scope: nil, choice: ^type_id, selection: concept_id} ->
        meta = Map.get(concept_metadata, {type_id, concept_id}, %{})
        if Map.has_key?(meta, "preparation_mode"), do: {type_id, concept_id}, else: nil

      _ ->
        nil
    end)
  end
end
