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
  alias ExTTRPGDev.RuleSystem.Effect
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
