defmodule ExTTRPGDev.Characters.Advancement do
  @moduledoc """
  Character advancement: applying award concepts to characters.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.apply_award/4`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystem.Expression
  alias ExTTRPGDev.RuleSystem.Vocabulary
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  # Bound to attributes for use in pattern-match positions; the names are
  # owned by ExTTRPGDev.RuleSystem.Vocabulary.
  @award_type Vocabulary.award_type()

  @doc """
  Applies an award concept to a character.

  See `ExTTRPGDev.Characters.apply_award/4` for documentation.
  """
  def apply_award(%LoadedSystem{} = system, %Character{} = character, award_id, value \\ nil) do
    with {:ok, meta} <- fetch_award_meta(system, award_id),
         {:ok, awarded} <- award_value(system, character, meta, value),
         {:ok, target} <- fetch_effect_target(meta) do
      updated = %{character | effects: character.effects ++ [%{target: target, value: awarded}]}

      updated = %{
        updated
        | pending_choice_slots: Characters.compute_pending_choice_slots(system, updated)
      }

      {:ok, updated, awarded}
    end
  end

  defp fetch_award_meta(system, award_id) do
    case system.concept_metadata[{@award_type, award_id}] do
      nil -> {:error, {:unknown_award, award_id}}
      meta -> {:ok, meta}
    end
  end

  defp award_value(_system, _character, %{"value_type" => "integer"}, value)
       when is_integer(value),
       do: {:ok, value}

  defp award_value(_system, _character, %{"value_type" => "integer"}, value)
       when not is_nil(value),
       do: {:error, :value_must_be_integer}

  defp award_value(system, character, %{"value_type" => "next_level_xp"}, nil) do
    case Characters.xp_to_next_level(system, character) do
      {:ok, xp_needed, _next_level} -> {:ok, xp_needed}
      {:error, reason} -> {:error, reason}
    end
  end

  defp award_value(_system, _character, %{"value_type" => "next_level_xp"}, value),
    do: {:ok, value}

  defp award_value(_system, _character, meta, nil),
    do: {:error, {:value_required, meta["value_type"]}}

  defp award_value(_system, _character, meta, _value),
    do: {:error, {:unsupported_value_type, meta["value_type"]}}

  defp fetch_effect_target(%{"effect_target" => target}) when is_binary(target) do
    case Expression.parse_ref(target) do
      {:ok, ref} -> {:ok, ref}
      :error -> {:error, {:invalid_effect_target, target}}
    end
  end

  defp fetch_effect_target(_meta), do: {:error, :missing_effect_target}
end
