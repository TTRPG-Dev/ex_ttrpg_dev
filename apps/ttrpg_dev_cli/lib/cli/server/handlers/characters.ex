defmodule ExTTRPGDev.CLI.Server.Handlers.Characters do
  @moduledoc """
  Handles the `characters.*` lifecycle commands: generation, persistence,
  display, rolls, awards, and choice resolution.

  The character-builder flow lives in `Handlers.Build`; inventory and
  preparation commands live in `Handlers.Inventory`.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Decision
  alias ExTTRPGDev.CLI.Serializer
  alias ExTTRPGDev.CLI.Server.Common
  alias ExTTRPGDev.CLI.Server.Errors
  alias ExTTRPGDev.RuleSystems

  def handle(%{"command" => "characters.gen", "system" => slug} = msg, state) do
    system = RuleSystems.load_system!(slug)
    decisions = Characters.random_decisions(system)
    character = Character.gen_character!(system, decisions)
    slots = Characters.compute_pending_choice_slots(system, character)

    character =
      Characters.auto_resolve_pending(system, %{character | pending_choice_slots: slots})

    temp_id = Integer.to_string(state.next_id)

    new_state = %{
      state
      | pending: Map.put(state.pending, temp_id, character),
        next_id: state.next_id + 1
    }

    data =
      Map.put(
        Serializer.serialize_character(system, character, nil, Common.parse_display_mode(msg)),
        :temp_id,
        temp_id
      )

    {:ok, data, new_state}
  end

  def handle(%{"command" => "characters.save", "temp_id" => temp_id}, state) do
    character = Common.fetch_pending!(state, temp_id)
    Characters.save_character!(character)
    new_state = %{state | pending: Map.delete(state.pending, temp_id)}
    {:ok, %{slug: character.metadata.slug}, new_state}
  end

  def handle(%{"command" => "characters.list"} = cmd, state) do
    system_filter = Map.get(cmd, "system")

    characters =
      Characters.list_characters!()
      |> Enum.map(&Characters.load_character!/1)
      |> Enum.filter(fn c ->
        system_filter == nil or c.metadata.rule_system == system_filter
      end)
      |> Enum.map(fn c ->
        %{
          slug: c.metadata.slug,
          name: c.name,
          rule_system: c.metadata.rule_system
        }
      end)

    {:ok, %{characters: characters}, state}
  end

  def handle(
        %{"command" => "characters.award", "character" => slug, "award" => award_id} = msg,
        state
      ) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)
    explicit_value = Map.get(msg, "value")

    case Characters.apply_award(system, character, award_id, explicit_value) do
      {:ok, updated, awarded_value} ->
        Characters.save_character!(updated, true)

        # The response reports :awarded_xp only when the award computed its
        # own amount (e.g. "level_up") rather than receiving an explicit one.
        extras = if explicit_value == nil, do: %{awarded_xp: awarded_value}, else: %{}

        data =
          system
          |> Common.character_with_choices_response(updated, slug, msg)
          |> Map.merge(extras)

        {:ok, data, state}

      {:error, reason} ->
        {:error, Errors.message(reason)}
    end
  end

  def handle(%{"command" => "characters.choices", "character" => slug} = msg, state) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)

    {_effects, resolved} = Characters.resolved_state(system, character)
    choices = Characters.pending_choices(system, character, resolved)

    {:ok,
     %{
       pending_choices:
         Serializer.serialize_choices_list(choices, system, Common.parse_display_mode(msg))
     }, state}
  end

  def handle(
        %{
          "command" => "characters.resolve_choice",
          "character" => slug,
          "progression" => progression_id,
          "selection" => selection
        } = msg,
        state
      ) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)

    case Characters.resolve_progression_choice(
           system,
           character,
           progression_id,
           selection,
           Map.get(msg, "value")
         ) do
      {:ok, updated} ->
        Characters.save_character!(updated, true)
        {:ok, Common.character_with_choices_response(system, updated, slug, msg), state}

      {:error, reason} ->
        {:error, Errors.message(reason)}
    end
  end

  def handle(
        %{
          "command" => "characters.resolve_choice",
          "character" => slug,
          "scope_type" => scope_type,
          "scope_id" => scope_id,
          "choice" => choice_id,
          "selection" => selection
        } = msg,
        state
      ) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)

    scope = {scope_type, scope_id}
    choice_def = Characters.fetch_choice_def!(system, scope, choice_id)
    valid = Characters.valid_sub_choices(system, scope, choice_def, character.decisions)
    Common.validate_concept_selection!(selection, valid)

    decision = %Decision{scope: scope, choice: choice_id, selection: selection}
    updated = %{character | decisions: character.decisions ++ [decision]}
    Characters.save_character!(updated, true)

    data = Common.character_with_choices_response(system, updated, slug, msg)

    {:ok, data, state}
  end

  def handle(%{"command" => "characters.random_resolve", "character" => slug} = msg, state) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)
    slots = Characters.compute_pending_choice_slots(system, character)
    character = %{character | pending_choice_slots: slots}

    {updated, resolutions} = Characters.random_resolve_all(system, character)
    Characters.save_character!(updated, true)

    data =
      Serializer.serialize_character(system, updated, slug, Common.parse_display_mode(msg))
      |> Map.put(:resolutions, Serializer.serialize_resolutions(resolutions, system))

    {:ok, data, state}
  end

  def handle(%{"command" => "characters.delete", "character" => slug}, state) do
    case Characters.delete_character(slug) do
      :ok -> {:ok, %{deleted: slug}, state}
      {:error, :not_found} -> {:error, "character not found: #{inspect(slug)}"}
    end
  end

  def handle(%{"command" => "characters.show", "character" => slug} = msg, state) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)
    data = Serializer.serialize_character(system, character, slug, Common.parse_display_mode(msg))
    {:ok, data, state}
  end

  def handle(
        %{
          "command" => "characters.roll",
          "character" => slug,
          "type" => type_id,
          "concept" => concept_id
        },
        state
      ) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)
    result = Characters.concept_roll!(system, character, type_id, concept_id)

    concept_name =
      case Map.get(system.concept_metadata, {type_id, concept_id}) do
        nil -> concept_id
        meta -> meta["name"] || concept_id
      end

    {:ok,
     %{
       concept_name: concept_name,
       dice: result.dice,
       rolls: result.rolls,
       bonus: result.bonus,
       total: result.total
     }, state}
  end

  def handle(%{"command" => cmd}, _state),
    do: {:error, "invalid arguments for command: #{inspect(cmd)}"}
end
