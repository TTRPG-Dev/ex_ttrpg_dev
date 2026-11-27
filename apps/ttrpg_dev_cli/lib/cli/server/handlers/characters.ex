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

  defguardp is_optional_string(value) when is_binary(value) or is_nil(value)

  def handle(%{"command" => "characters.gen", "system" => slug} = msg, state) do
    system = RuleSystems.load_system!(slug)
    decisions = Characters.random_decisions(system)
    character = Character.gen_character!(system, decisions)

    {:ok, %{slots: slots, errors: slot_errors}} =
      Characters.compute_pending_choice_slots(system, character)

    character =
      Characters.auto_resolve_pending(system, %{character | pending_choice_slots: slots})

    temp_id = Integer.to_string(state.next_id)

    new_state = %{
      state
      | pending: Map.put(state.pending, temp_id, character),
        next_id: state.next_id + 1
    }

    data =
      Serializer.serialize_character(system, character, nil, Common.parse_display_mode(msg))
      |> Map.put(:temp_id, temp_id)
      |> Map.put(:pending_choice_slot_errors, slot_errors)

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
      |> Enum.flat_map(fn slug ->
        case Characters.load_character(slug) do
          {:ok, c} -> [c]
          {:error, _reason} -> []
        end
      end)
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
    system = RuleSystems.load_system_for!(character)
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

  def handle(%{"command" => "characters.level_up", "character" => slug} = msg, state) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system_for!(character)

    opts =
      case msg do
        %{"class" => class_id} when is_binary(class_id) -> [class: class_id]
        _ -> []
      end

    case Characters.level_up(system, character, opts) do
      {:ok, updated} ->
        Characters.save_character!(updated, true)
        {:ok, Common.character_with_choices_response(system, updated, slug, msg), state}

      {:error, reason} ->
        {:error, Errors.message(reason)}
    end
  end

  def handle(%{"command" => "characters.choices", "character" => slug} = msg, state) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system_for!(character)

    {_effects, resolved} = Characters.resolved_state(system, character)

    {:ok, %{choices: choices, errors: errors}} =
      Characters.pending_choices(system, character, resolved)

    {:ok,
     %{
       pending_choices:
         Serializer.serialize_choices_list(choices, system, Common.parse_display_mode(msg)),
       pending_choice_errors: errors
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
    system = RuleSystems.load_system_for!(character)

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
    system = RuleSystems.load_system_for!(character)

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
    system = RuleSystems.load_system_for!(character)

    {:ok, %{slots: slots, errors: slot_errors}} =
      Characters.compute_pending_choice_slots(system, character)

    character = %{character | pending_choice_slots: slots}

    {updated, resolutions} = Characters.random_resolve_all(system, character)
    Characters.save_character!(updated, true)

    data =
      Serializer.serialize_character(system, updated, slug, Common.parse_display_mode(msg))
      |> Map.put(:resolutions, Serializer.serialize_resolutions(resolutions, system))
      |> Map.put(:pending_choice_slot_errors, slot_errors)

    {:ok, data, state}
  end

  def handle(%{"command" => "characters.delete", "character" => slug}, state) do
    case Characters.delete_character(slug) do
      :ok -> {:ok, %{deleted: slug}, state}
      {:error, :not_found} -> {:error, "character not found: #{inspect(slug)}"}
    end
  end

  # Without a "slug" (or with null), the copy takes the first free
  # <source>_copy_N. Any other non-string "slug" matches neither clause, so
  # it's refused as invalid arguments rather than reaching the library.
  def handle(%{"command" => "characters.copy", "character" => source, "slug" => slug}, state)
      when is_binary(source) and is_optional_string(slug),
      do: copy(source, slug, state)

  def handle(%{"command" => "characters.copy", "character" => source} = cmd, state)
      when is_binary(source) and not is_map_key(cmd, "slug"),
      do: copy(source, nil, state)

  def handle(%{"command" => "characters.show", "character" => slug} = msg, state) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system_for!(character)
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
    system = RuleSystems.load_system_for!(character)
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

  # The copy is the source as saved, renamed and re-keyed: everything else
  # (rolls, decisions, effects, inventory, pending slots) carries over, so
  # it's usable at once. Saving without overwrite means a slug taken
  # between choosing it and writing is refused, never clobbered.
  defp copy(source, new_slug, state) do
    with {:ok, character} <- load_copy_source(source),
         copy = rename_copy(character, source),
         {:ok, slug} <- copy_to(copy, source, new_slug) do
      {:ok, %{copied: source, created: slug, name: copy.name}, state}
    else
      {:error, reason} -> {:error, copy_error_message(source, new_slug, reason)}
    end
  end

  # A source slug that isn't valid can't name a saved character, so it's
  # reported as not found rather than as a bad slug the user didn't type
  # for the copy.
  defp load_copy_source(source) do
    case Characters.load_character(source) do
      {:error, {:invalid_slug, _}} -> {:error, :not_found}
      result -> result
    end
  end

  # A character saved without a name, or with a blank one, is named after
  # its slug, so the copy still reads as one in characters list.
  defp rename_copy(%Character{name: name} = character, source) do
    base = if is_binary(name) and String.trim(name) != "", do: name, else: source
    %{character | name: "#{base} (copy)"}
  end

  defp copy_to(copy, source, nil) do
    with {:ok, slugs} <- Characters.list_characters() do
      copy_to_next_free(copy, source, 1, MapSet.new(slugs))
    end
  end

  defp copy_to(copy, _source, slug) do
    with :ok <- save_as(copy, slug), do: {:ok, slug}
  end

  # Each refused candidate is a saved character, so this ends after at
  # most that many tries.
  defp copy_to_next_free(copy, source, n, listed) do
    slug = "#{source}_copy_#{n}"

    if MapSet.member?(listed, slug),
      do: copy_to_next_free(copy, source, n + 1, listed),
      else: try_copy_to(copy, source, n, listed)
  end

  defp try_copy_to(copy, source, n, listed) do
    slug = "#{source}_copy_#{n}"

    case save_as(copy, slug) do
      :ok -> {:ok, slug}
      {:error, :already_exists} -> copy_to_next_free(copy, source, n + 1, listed)
      {:error, {:invalid_slug, _}} -> {:error, :no_derivable_slug}
      error -> error
    end
  end

  defp save_as(copy, slug),
    do: Characters.save_character(%{copy | metadata: %{copy.metadata | slug: slug}})

  defp copy_error_message(source, _new_slug, :not_found),
    do: "character not found: #{inspect(source)}"

  defp copy_error_message(_source, slug, :already_exists),
    do: "a character with slug #{inspect(slug)} already exists"

  defp copy_error_message(_source, slug, {:invalid_slug, _}),
    do: "invalid slug #{inspect(slug)}: use letters, digits, _ and - (and keep it short)"

  # Only reachable without a given slug, when the next free <source>_copy_N
  # is too long to be a slug: from the first try if the source's own slug
  # is near the limit, or later if only the growing N pushes it over (e.g.
  # _copy_9 fits but _copy_10 doesn't).
  defp copy_error_message(source, nil, :no_derivable_slug) do
    "can't derive a slug for the copy from #{inspect(source)}; " <>
      "give one: characters copy #{source} <new_slug>"
  end

  defp copy_error_message(source, _new_slug, {:invalid_character_data, message}),
    do: "cannot copy character #{inspect(source)}: its saved data can't be read: #{message}"

  defp copy_error_message(source, _new_slug, reason),
    do: "cannot copy character #{inspect(source)}: #{inspect(reason)}"
end
