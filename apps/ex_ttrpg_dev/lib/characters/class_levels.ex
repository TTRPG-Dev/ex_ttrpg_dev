defmodule ExTTRPGDev.Characters.ClassLevels do
  @moduledoc """
  Class levels: splitting a character's total level among the classes of
  the system's `class_concept_type`, from the class chosen at creation and
  the character's `level_classes` record.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.class_levels/2`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Decision
  alias ExTTRPGDev.Characters.Effects
  alias ExTTRPGDev.Characters.Leveling
  alias ExTTRPGDev.Characters.Progression
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystem.Expression
  alias ExTTRPGDev.RuleSystem.Vocabulary
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Returns each class the character has levels in, with its level.

  See `ExTTRPGDev.Characters.class_levels/2` for documentation.
  """
  def class_levels(%LoadedSystem{} = system, %Character{} = character) do
    case class_type(system) do
      nil -> {:error, :class_levels_not_enabled}
      class_type -> {:ok, resolved_class_levels(system, character, class_type)}
    end
  end

  defp resolved_class_levels(system, character, class_type) do
    {_effects, resolved} = Effects.resolved_state(system, character)
    level_field = Vocabulary.class_level_field()

    for {{^class_type, id, ^level_field}, level} <- resolved, level > 0, into: %{} do
      {id, trunc(level)}
    end
  end

  @doc """
  Raises a character to its next level, recording which class gained it.

  See `ExTTRPGDev.Characters.level_up/3` for documentation.
  """
  def level_up(%LoadedSystem{} = system, %Character{} = character, opts \\ []) do
    with {:ok, xp_needed, next_level} <- Leveling.xp_to_next_level(system, character),
         {:ok, level_classes} <- record_level(system, character, next_level, opts[:class]) do
      xp_effect = %Effect{target: Leveling.xp_effect_target(system), value: xp_needed}

      updated = %{
        character
        | effects: character.effects ++ [xp_effect],
          level_classes: level_classes
      }

      {:ok, %{slots: slots}} = Progression.compute_pending_choice_slots(system, updated)
      {:ok, %{updated | pending_choice_slots: slots}}
    end
  end

  defp record_level(system, character, next_level, class_id) do
    case {class_type(system), class_id} do
      {nil, nil} -> {:ok, character.level_classes}
      {nil, _class_id} -> {:error, :class_levels_not_enabled}
      _ -> record_class_level(system, character, next_level, class_id)
    end
  end

  defp record_class_level(system, character, next_level, class_id) do
    with first when not is_nil(first) <- first_class(system, character),
         class_id = class_id || first,
         :ok <- check_class_exists(system, class_id),
         held = held_classes(character, first, next_level - 1),
         :ok <- check_can_take(system, character, class_id, held) do
      # Levels reached without a record (e.g. through XP awards) went to
      # the first class; writing that down keeps the new entry at the
      # level it's for.
      reached = next_level - 2
      recorded = Enum.take(character.level_classes, reached)
      padding = List.duplicate(first, reached - length(recorded))

      {:ok, recorded ++ padding ++ [class_id]}
    else
      nil -> {:error, :no_class}
      {:error, _} = error -> error
    end
  end

  defp check_class_exists(system, class_id) do
    if Map.has_key?(system.concept_metadata, {class_type(system), class_id}),
      do: :ok,
      else: {:error, {:unknown_class, class_id}}
  end

  # The classes the character has levels in at `level`.
  defp held_classes(character, first, level) do
    [first | Enum.take(character.level_classes, max(level - 1, 0))] |> Enum.uniq()
  end

  # Gaining a level in a class the character already has is always allowed.
  # Taking a new class needs that class to declare a multiclass table, and
  # the prerequisites of the new class and of every class already held
  # (each declared in its multiclass table) to be met.
  defp check_can_take(system, character, class_id, held) do
    cond do
      class_id in held ->
        :ok

      multiclass_table(system, class_id) == nil ->
        {:error, {:not_multiclassable, class_id}}

      true ->
        {_effects, resolved} = Effects.resolved_state(system, character)

        Enum.find_value([class_id | held], :ok, fn id ->
          check_prerequisite(system, id, resolved)
        end)
    end
  end

  # nil when met (or undeclared), so it can drive Enum.find_value/3.
  defp check_prerequisite(system, class_id, resolved) do
    case multiclass_table(system, class_id) do
      %{"prerequisite" => expr} when is_binary(expr) ->
        case Expression.evaluate(expr, resolved) do
          {:ok, true} -> nil
          {:ok, n} when is_number(n) and n != 0 -> nil
          {:ok, _} -> {:error, {:multiclass_prerequisite_not_met, class_id}}
          {:error, reason} -> {:error, {:invalid_multiclass_prerequisite, class_id, reason}}
        end

      _ ->
        nil
    end
  end

  defp multiclass_table(system, class_id) do
    get_in(system.concept_metadata, [{class_type(system), class_id}, Vocabulary.multiclass_key()])
  end

  @doc false
  # The system's class concept type, or `nil` when class levels aren't
  # enabled. Tolerates the partial module maps hand-built systems carry.
  def class_type(%LoadedSystem{module: %{class_concept_type: class_type}}), do: class_type
  def class_type(_system), do: nil

  @doc false
  # The class chosen at creation: the root decision for the class concept
  # type. `nil` when the system has no class levels or the character has
  # no class yet.
  def first_class(%LoadedSystem{} = system, %Character{} = character) do
    case class_type(system) do
      nil -> nil
      class_type -> first_class_of_type(character.decisions, class_type)
    end
  end

  defp first_class_of_type(decisions, class_type) do
    Enum.find_value(decisions, fn
      %Decision{scope: nil, choice: ^class_type, selection: id} -> id
      _ -> nil
    end)
  end

  @doc false
  # The effects that split the total level among the character's classes.
  #
  # Each is conditioned on the total level rather than fixed, so evaluating
  # at a past level (Leveling.evaluate_at_level/6) counts only the levels
  # gained by then. Levels past the end of `level_classes` went to the
  # first class.
  def level_effects(%LoadedSystem{} = system, %Character{} = character) do
    case first_class(system, character) do
      nil -> []
      first -> level_effects(system, character, first)
    end
  end

  defp level_effects(system, character, first) do
    class_type = system.module.class_concept_type
    level_field = Vocabulary.class_level_field()
    total = "(#{system.module.level_node})"
    recorded = length(character.level_classes)
    target = fn id -> {class_type, id, level_field} end

    recorded_effects =
      character.level_classes
      |> Enum.with_index(2)
      |> Enum.map(fn {id, level} ->
        %Effect{target: target.(id), value: 1, when: "#{total} >= #{level}"}
      end)

    unrecorded = %Effect{
      target: target.(first),
      value: "#{total} - #{recorded + 1}",
      when: "#{total} > #{recorded + 1}"
    }

    [%Effect{target: target.(first), value: 1} | recorded_effects] ++ [unrecorded]
  end
end
