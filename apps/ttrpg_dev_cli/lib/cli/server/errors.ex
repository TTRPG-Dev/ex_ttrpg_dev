defmodule ExTTRPGDev.CLI.Server.Errors do
  @moduledoc """
  The single formatting boundary between library error reasons and protocol
  error messages.

  Every domain `{:error, reason}` a handler surfaces must be rendered here so
  the same condition always produces the same message and raw Elixir terms
  never reach the frontend. New library error reasons should get a clause
  here rather than fall through to the inspected-term fallback.
  """

  # --- awards ---

  def message({:unknown_award, id}), do: "unknown award: #{inspect(id)}"

  def message({:value_required, value_type}),
    do:
      "award #{inspect(value_type)} requires an explicit value; use: characters award <slug> #{value_type} <value>"

  def message({:unsupported_value_type, value_type}),
    do: "unsupported award value_type: #{inspect(value_type)}"

  def message(:max_level), do: "character is already at max level"
  def message(:no_level_thresholds), do: "system does not define level XP thresholds"

  # --- progression choices ---

  def message({:unknown_progression, id}), do: "unknown progression: #{inspect(id)}"

  def message({:no_pending_choice, id}),
    do: "no pending choice for progression: #{inspect(id)}"

  def message({:invalid_selection, selection}),
    do: "#{inspect(selection)} is not available for this character and progression"

  def message(:value_required), do: "value is required for this progression"
  def message(:value_must_be_integer), do: "value must be an integer"
  def message(:missing_effect_target), do: "no effect_target configured"

  def message({:invalid_effect_target, target}),
    do: "invalid effect target: #{inspect(target)}"

  def message({:inventory_error, reason}),
    do: "failed to add to inventory: " <> message(reason)

  # --- preparation / activation ---

  def message({:ineligible_items, ids}), do: "ineligible items: #{Enum.join(ids, ", ")}"

  def message({:exceeds_cap, count, cap}),
    do: "cannot prepare more than #{cap} (given: #{count})"

  def message({:mode_not_prepared, mode}),
    do: "items of this type cannot be manually activated (mode: \"#{mode}\")"

  def message(:no_preparation_class),
    do: "no class with preparation_mode found for this character"

  def message(:no_preparation_cap), do: "class has no preparation cap"

  def message({:unknown_inventory_type, type_id}),
    do: "unknown inventory type: #{inspect(type_id)}"

  def message({:not_a_preparation_type, type_id}),
    do: "inventory type #{inspect(type_id)} does not support preparation"

  # --- inventory items ---

  def message({:not_inventoriable, concept_type}),
    do: "concepts of type #{inspect(concept_type)} cannot be added to inventory"

  def message({:unknown_field, name}), do: "unknown inventory field: #{inspect(name)}"
  def message({:invalid_type, expected}), do: "value must be of type #{expected}"

  def message({:invalid_enum_value, value, allowed}),
    do: "#{inspect(value)} is not one of: #{Enum.join(allowed, ", ")}"

  def message({:below_minimum, value, min}), do: "#{value} is below the minimum of #{min}"
  def message({:above_maximum, value, max}), do: "#{value} is above the maximum of #{max}"

  # Defensive fallback for reasons not yet given a clause; should stay
  # unreachable for every reason the library documents.
  def message(reason), do: inspect(reason)
end
