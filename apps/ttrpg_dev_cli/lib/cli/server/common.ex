defmodule ExTTRPGDev.CLI.Server.Common do
  @moduledoc """
  Request and response helpers shared by the server's handler modules.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.CLI.Serializer

  @doc """
  Parses the optional `display_mode` field of a request into the atom the
  serializer's display templates understand. Unknown values fall back to
  `:default`.
  """
  def parse_display_mode(msg) do
    case Map.get(msg, "display_mode", "default") do
      "verbose" -> :verbose
      "succinct" -> :succinct
      _ -> :default
    end
  end

  @doc """
  The standard response body for mutate-then-report handlers: the character
  serialized against a single DAG evaluation, plus its recomputed pending
  choices rendered in the request's display mode.
  """
  def character_with_choices_response(system, character, slug, msg) do
    {_effects, resolved} = Characters.resolved_state(system, character)
    choices = Characters.pending_choices(system, character, resolved)
    mode = parse_display_mode(msg)

    system
    |> Serializer.serialize_character(character, slug, mode, resolved)
    |> Map.put(:pending_choices, Serializer.serialize_choices_list(choices, system, mode))
  end

  @doc """
  Fetches a generated-but-unsaved character held under `temp_id`, raising
  (toward the dispatch rescue boundary) when none exists.
  """
  def fetch_pending!(state, temp_id) do
    Map.get(state.pending, temp_id) || raise("no pending character: #{inspect(temp_id)}")
  end

  @doc """
  Raises (toward the dispatch rescue boundary) unless `selection` is one of
  `valid_options`.
  """
  def validate_concept_selection!(selection, valid_options) do
    unless selection in valid_options do
      raise("#{inspect(selection)} is not available for this character and progression")
    end
  end
end
