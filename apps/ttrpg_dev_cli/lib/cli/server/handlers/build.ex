defmodule ExTTRPGDev.CLI.Server.Handlers.Build do
  @moduledoc """
  Handles the `characters.build_*` commands: the interactive character
  builder flow. A character under construction is held in server state under
  a `temp_id` until `build_finish` (or `characters.save`) persists it.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Decision
  alias ExTTRPGDev.CLI.Serializer
  alias ExTTRPGDev.CLI.Server.Common
  alias ExTTRPGDev.RuleSystems

  def handle(
        %{"command" => "characters.build_start", "system" => slug, "name" => name},
        state
      ) do
    system = RuleSystems.load_system!(slug)
    character = Character.gen_character!(system, [])

    slug = Character.slugify(name)
    character = %{character | name: name, metadata: %{character.metadata | slug: slug}}
    temp_id = Integer.to_string(state.next_id)
    pending = Map.put(state.pending, temp_id, character)
    new_state = %{state | pending: pending, next_id: state.next_id + 1}

    building_choices = Serializer.serialize_building_choices(system)
    {:ok, %{temp_id: temp_id, building_choices: building_choices}, new_state}
  end

  def handle(
        %{
          "command" => "characters.build_select",
          "temp_id" => temp_id,
          "concept_type" => concept_type,
          "concept_id" => concept_id
        },
        state
      ) do
    character = Common.fetch_pending!(state, temp_id)
    system = RuleSystems.load_system!(character.metadata.rule_system)
    decision = %Decision{scope: nil, choice: concept_type, selection: concept_id}
    updated = %{character | decisions: character.decisions ++ [decision]}

    sub_choices =
      Serializer.serialize_concept_sub_choices(
        concept_type,
        concept_id,
        updated.decisions,
        system
      )

    new_state = %{state | pending: Map.put(state.pending, temp_id, updated)}
    {:ok, %{sub_choices: sub_choices}, new_state}
  end

  def handle(
        %{
          "command" => "characters.build_resolve_sub",
          "temp_id" => temp_id,
          "scope_type" => scope_type,
          "scope_id" => scope_id,
          "choice" => choice_id,
          "selection" => selection
        },
        state
      ) do
    character = Common.fetch_pending!(state, temp_id)
    system = RuleSystems.load_system!(character.metadata.rule_system)
    scope = {scope_type, scope_id}
    choice_def = Characters.fetch_choice_def!(system, scope, choice_id)
    valid = Characters.valid_sub_choices(system, scope, choice_def, character.decisions)
    Common.validate_concept_selection!(selection, valid)
    decision = %Decision{scope: scope, choice: choice_id, selection: selection}
    updated = %{character | decisions: character.decisions ++ [decision]}

    sub_choices =
      Serializer.serialize_concept_sub_choices(scope_type, scope_id, updated.decisions, system)

    new_state = %{state | pending: Map.put(state.pending, temp_id, updated)}
    {:ok, %{sub_choices: sub_choices}, new_state}
  end

  def handle(%{"command" => "characters.build_finish", "temp_id" => temp_id} = msg, state) do
    char = Common.fetch_pending!(state, temp_id)
    sys = RuleSystems.load_system!(char.metadata.rule_system)
    inv = Character.inventory_from_decisions(char.decisions, sys)
    slots = Characters.compute_pending_choice_slots(sys, %{char | inventory: inv})
    updated = %{char | inventory: inv, pending_choice_slots: slots}
    Characters.save_character!(updated)
    new_state = %{state | pending: Map.delete(state.pending, temp_id)}
    data = Common.character_with_choices_response(sys, updated, updated.metadata.slug, msg)

    {:ok, data, new_state}
  end

  def handle(%{"command" => cmd}, _state),
    do: {:error, "invalid arguments for command: #{inspect(cmd)}"}
end
