defmodule ExTTRPGDev.Characters.Advancement do
  @moduledoc """
  Character advancement: applying award concepts and resolving progression
  choices.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.apply_award/4`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystem.Expression
  alias ExTTRPGDev.RuleSystem.Vocabulary
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  # Bound to attributes for use in pattern-match positions; the names are
  # owned by ExTTRPGDev.RuleSystem.Vocabulary.
  @award_type Vocabulary.award_type()
  @progression_type Vocabulary.progression_type()

  @doc """
  Applies an award concept to a character.

  See `ExTTRPGDev.Characters.apply_award/4` for documentation.
  """
  def apply_award(%LoadedSystem{} = system, %Character{} = character, award_id, value \\ nil) do
    with {:ok, meta} <- fetch_award_meta(system, award_id),
         {:ok, awarded} <- award_value(system, character, meta, value),
         {:ok, target} <- fetch_effect_target(meta) do
      updated = %{
        character
        | effects: character.effects ++ [%Effect{target: target, value: awarded}]
      }

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

  @doc """
  Resolves a pending progression choice for a character.

  See `ExTTRPGDev.Characters.resolve_progression_choice/5` for documentation.
  """
  def resolve_progression_choice(system, character, progression_id, selection, value \\ nil)

  def resolve_progression_choice(
        %LoadedSystem{} = system,
        %Character{} = character,
        progression_id,
        selection,
        value
      ) do
    case system.concept_metadata[{@progression_type, progression_id}] do
      nil ->
        {:error, {:unknown_progression, progression_id}}

      %{"type" => _} ->
        resolve_selection_progression(system, character, progression_id, selection)

      meta ->
        resolve_value_progression(character, progression_id, meta, {selection, value})
    end
  end

  defp resolve_selection_progression(system, character, progression_id, selection) do
    {_effects, resolved} = Characters.resolved_state(system, character)
    choices = Characters.pending_choices(system, character, resolved)

    entry =
      Enum.find(choices, fn c ->
        c.type == :pending and c.id == progression_id and not Map.has_key?(c, :scope_type)
      end)

    cond do
      entry == nil ->
        {:error, {:no_pending_choice, progression_id}}

      selection not in entry.options ->
        {:error, {:invalid_selection, selection}}

      true ->
        decision =
          Characters.next_progression_decision(character.decisions, progression_id, selection)

        with_decision = %{
          character
          | decisions: character.decisions ++ [decision],
            pending_choice_slots: consume_slot(character.pending_choice_slots, progression_id)
        }

        case Characters.add_to_typed_inventory(system, with_decision, progression_id, selection) do
          {:ok, updated} -> {:ok, updated}
          {:error, reason} -> {:error, {:inventory_error, reason}}
        end
    end
  end

  defp resolve_value_progression(character, progression_id, meta, {selection, value}) do
    with :ok <- validate_progression_value(value),
         {:ok, target} <- fetch_effect_target(meta) do
      decision =
        Characters.next_progression_decision(character.decisions, progression_id, selection)

      {:ok,
       %{
         character
         | effects: character.effects ++ [%Effect{target: target, value: value}],
           decisions: character.decisions ++ [decision]
       }}
    end
  end

  defp validate_progression_value(value) when is_integer(value), do: :ok
  defp validate_progression_value(nil), do: {:error, :value_required}
  defp validate_progression_value(_), do: {:error, :value_must_be_integer}

  @doc """
  Fetches the definition of a sub-choice declared by a concept.

  See `ExTTRPGDev.Characters.fetch_choice_def!/3` for documentation.
  """
  def fetch_choice_def!(system, {type, id}, choice_id) do
    get_in(system.concept_metadata, [{type, id}, "choices", choice_id]) ||
      raise("unknown choice #{inspect(choice_id)} on #{type}(#{id})")
  end

  @doc """
  Returns the currently valid selections for a concept sub-choice.

  See `ExTTRPGDev.Characters.valid_sub_choices/4` for documentation.
  """
  def valid_sub_choices(system, {scope_type, scope_id} = scope, choice_def, decisions) do
    choice_type = choice_def["type"]
    raw_options = sub_choice_options(system, choice_def)

    already_chosen =
      decisions
      |> Enum.filter(fn
        %{scope: ^scope, choice: choice} ->
          cd =
            get_in(system.concept_metadata, [{scope_type, scope_id}, "choices", choice]) || %{}

          cd["type"] == choice_type

        _ ->
          false
      end)
      |> MapSet.new(& &1.selection)

    Enum.reject(raw_options, &MapSet.member?(already_chosen, &1))
  end

  @doc """
  The raw option list for a sub-choice definition.

  See `ExTTRPGDev.Characters.sub_choice_options/2` for documentation.
  """
  def sub_choice_options(system, choice_def) do
    case choice_def["options"] do
      options when is_list(options) ->
        options

      _ ->
        choice_type = choice_def["type"]

        system.concept_metadata
        |> Enum.filter(fn {{t, _}, _} -> t == choice_type end)
        |> Enum.map(fn {{_, id}, _} -> id end)
        |> Enum.sort()
    end
  end

  defp consume_slot(pending_choice_slots, progression_id) do
    case Enum.split_while(pending_choice_slots, &(&1.progression_id != progression_id)) do
      {before_slots, [_ | after_slots]} -> before_slots ++ after_slots
      _ -> pending_choice_slots
    end
  end
end
