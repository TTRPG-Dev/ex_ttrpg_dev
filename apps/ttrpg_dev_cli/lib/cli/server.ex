defmodule ExTTRPGDev.CLI.Server do
  @moduledoc """
  JSON server mode for inter-process communication.

  Reads newline-delimited JSON commands from stdin, writes newline-delimited JSON
  responses to stdout. Intended to be driven by the Rust CLI frontend.

  Launched via `ttrpg-dev-engine --server`.

  ## Protocol

  Each request is a single line of JSON with a `command` field; each response
  is a single line of JSON:

      {"status": "ok", "data": {...}}
      {"status": "error", "message": "..."}

  Every request additionally accepts an optional `"display_mode"` field
  (`"default"`, `"verbose"`, or `"succinct"`) controlling how concept labels
  are rendered.

  ### Dice

      {"command": "roll", "dice": "3d6"}
      {"command": "roll", "dice": "3d6,1d20"}

  ### Systems

      {"command": "systems.list"}
      {"command": "systems.show", "system": "dnd_5e_srd"}
      {"command": "systems.show", "system": "dnd_5e_srd", "concept_type": "skill"}
      {"command": "systems.show", "system": "dnd_5e_srd", "concept_type": "skill", "concept_id": "acrobatics"}
      {"command": "systems.create", "name": "My Homebrew", "version": "1.0.0", "publisher": "Acme Games"}
      {"command": "systems.copy", "system": "dnd_5e_srd", "slug": "my_homebrew"}
      {"command": "systems.delete", "system": "my_homebrew"}
      {"command": "systems.concept_type.add", "system": "my_homebrew", "name": "Feat", "display_template": "{{name}} (Cost: {{cost}})"}

  ### Characters

      {"command": "characters.gen", "system": "dnd_5e_srd"}
      {"command": "characters.save", "temp_id": "1"}
      {"command": "characters.list"}
      {"command": "characters.list", "system": "dnd_5e_srd"}
      {"command": "characters.show", "character": "thorin-stoneback"}
      {"command": "characters.copy", "character": "thorin-stoneback"}
      {"command": "characters.copy", "character": "thorin-stoneback", "slug": "thorin-backup"}
      {"command": "characters.delete", "character": "thorin-stoneback"}
      {"command": "characters.roll", "character": "thorin-stoneback", "type": "skill", "concept": "acrobatics"}
      {"command": "characters.award", "character": "thorin-stoneback", "award": "experience_points", "value": 300}
      {"command": "characters.award", "character": "thorin-stoneback", "award": "level_up"}
      {"command": "characters.level_up", "character": "thorin-stoneback"}
      {"command": "characters.level_up", "character": "thorin-stoneback", "class": "wizard"}
      {"command": "characters.choices", "character": "thorin-stoneback"}
      {"command": "characters.resolve_choice", "character": "thorin-stoneback", "progression": "hp_per_level", "value": 7, "selection": "rolled"}
      {"command": "characters.resolve_choice", "character": "thorin-stoneback", "progression": "cantrips", "selection": "fire_bolt"}
      {"command": "characters.resolve_choice", "character": "thorin-stoneback", "scope_type": "feat", "scope_id": "ability_score_improvement", "choice": "asi_point_1", "selection": "strength"}
      {"command": "characters.random_resolve", "character": "thorin-stoneback"}

  ### Character builder

  `build_start` generates an empty character and returns a `temp_id` plus the
  root building choices (race, class, background, ...). `build_select` picks a
  root concept and returns its pending sub-choices; `build_resolve_sub`
  answers one sub-choice. `build_finish` derives starting inventory and
  pending choice slots, saves the character, and releases the `temp_id`.

      {"command": "characters.build_start", "system": "dnd_5e_srd", "name": "Thorin Stoneback"}
      {"command": "characters.build_select", "temp_id": "1", "concept_type": "class", "concept_id": "cleric"}
      {"command": "characters.build_resolve_sub", "temp_id": "1", "scope_type": "class", "scope_id": "cleric", "choice": "skill_proficiency_1", "selection": "history"}
      {"command": "characters.build_finish", "temp_id": "1"}

  ### Inventory and preparation

      {"command": "characters.inventory", "character": "thorin-stoneback"}
      {"command": "characters.inventory.add", "character": "thorin-stoneback", "type": "equipment", "id": "longsword"}
      {"command": "characters.inventory.add", "character": "thorin-stoneback", "type": "equipment", "id": "chain_mail", "fields": {"equipped": true}}
      {"command": "characters.inventory.set", "character": "thorin-stoneback", "index": 0, "field": "equipped", "value": true}
      {"command": "characters.spells", "character": "thorin-stoneback"}
      {"command": "characters.activate", "character": "thorin-stoneback", "verb": "prepare", "items": ["bless", "cure_wounds"]}
      {"command": "characters.activate", "character": "thorin-stoneback", "verb": "equip", "items": [0]}

  Generated-but-unsaved characters are held in memory under a `temp_id` until
  `characters.save` / `characters.build_finish` is called or the server exits.
  """

  require Logger

  alias ExTTRPGDev.CLI.Server.Handlers
  alias ExTTRPGDev.RuleSystems

  @type state :: %{
          pending: %{String.t() => ExTTRPGDev.Characters.Character.t()},
          next_id: non_neg_integer()
        }

  # Command -> handler-module registry. Every implemented protocol command
  # must appear here; a command absent from this map is answered with an
  # "unknown command" error.
  @handlers %{
    "roll" => Handlers.Dice,
    "systems.list" => Handlers.Systems,
    "systems.show" => Handlers.Systems,
    "systems.create" => Handlers.Systems,
    "systems.copy" => Handlers.Systems,
    "systems.delete" => Handlers.Systems,
    "systems.concept_type.add" => Handlers.Systems,
    "characters.gen" => Handlers.Characters,
    "characters.save" => Handlers.Characters,
    "characters.list" => Handlers.Characters,
    "characters.show" => Handlers.Characters,
    "characters.copy" => Handlers.Characters,
    "characters.delete" => Handlers.Characters,
    "characters.roll" => Handlers.Characters,
    "characters.award" => Handlers.Characters,
    "characters.level_up" => Handlers.Characters,
    "characters.choices" => Handlers.Characters,
    "characters.resolve_choice" => Handlers.Characters,
    "characters.random_resolve" => Handlers.Characters,
    "characters.build_start" => Handlers.Build,
    "characters.build_select" => Handlers.Build,
    "characters.build_resolve_sub" => Handlers.Build,
    "characters.build_finish" => Handlers.Build,
    "characters.inventory" => Handlers.Inventory,
    "characters.inventory.add" => Handlers.Inventory,
    "characters.inventory.set" => Handlers.Inventory,
    "characters.spells" => Handlers.Inventory,
    "characters.activate" => Handlers.Inventory
  }

  def run do
    log_to_stderr()
    Logger.configure(level: :info)
    sync_rule_systems()
    loop(%{pending: %{}, next_id: 1})
  end

  # The engine is the host application for the library, so it decides when
  # installed rule systems may be replaced: once, at startup, before any
  # command is served, so content never changes under a session. A failed
  # sync is logged but not fatal: installed systems still load, and an
  # absent bundled system is still seeded on first load.
  @doc false
  def sync_rule_systems do
    case RuleSystems.sync_bundled() do
      {:ok, _results} -> :ok
      {:error, reason} -> Logger.error("rule system sync failed: #{inspect(reason)}")
    end

    :ok
  end

  # stdout is the protocol channel: the frontend parses every line on it as
  # a response, so a log line there would be read as a malformed response
  # (or worse, consumed in place of the real one). Logger's default handler
  # writes to standard_io, and a running handler's output type can't be
  # changed, so the handler is replaced with one writing to stderr, which
  # the frontend passes through to the user.
  @doc false
  def log_to_stderr do
    with {:ok, %{config: %{type: :standard_io}} = handler} <-
           :logger.get_handler_config(:default) do
      :ok = :logger.remove_handler(:default)

      :ok =
        :logger.add_handler(
          :default,
          :logger_std_h,
          handler
          |> Map.take([:level, :filters, :filter_default, :formatter])
          |> Map.put(:config, %{type: :standard_error})
        )
    end

    :ok
  end

  # The single rescue boundary for command handling: any exception raised by a
  # handler becomes a protocol error response, and the caller's state is
  # returned unchanged. Handlers build their new state and return it only on
  # success, so a mid-handler raise cannot leak partial mutations.
  @doc false
  def handle_command(msg, state) do
    case route(msg, state) do
      {:ok, data, new_state} -> {ok(data), new_state}
      {:error, message} -> {error(message), state}
    end
  rescue
    e -> {error(Exception.message(e)), state}
  end

  defp route(%{"command" => command} = msg, state) do
    case Map.fetch(@handlers, command) do
      {:ok, handler} -> handler.handle(msg, state)
      :error -> {:error, "unknown command: #{inspect(command)}"}
    end
  end

  defp route(_msg, _state), do: {:error, "request must have a \"command\" field"}

  defp loop(state) do
    case IO.gets("") do
      :eof ->
        :ok

      {:error, _reason} ->
        :ok

      line when is_binary(line) ->
        {response, new_state} =
          line
          |> String.trim()
          |> dispatch(state)

        IO.puts(encode_response(response))
        loop(new_state)
    end
  end

  # Jason.encode/2 returns {:error, _} rather than raising for a value with
  # no Jason.Encoder implementation (e.g. a raw tuple that slipped into a
  # handler's response data), so falling back here keeps one bad response
  # from crashing the whole server loop. Public (like handle_command/2)
  # so this fallback is directly testable without driving stdin/stdout.
  @doc false
  def encode_response(response) do
    case Jason.encode(response) do
      {:ok, json} ->
        json

      {:error, reason} ->
        Jason.encode!(error("response was not JSON-encodable: #{inspect(reason)}"))
    end
  end

  defp dispatch("", state), do: {ok(%{}), state}

  defp dispatch(line, state) do
    case Jason.decode(line) do
      {:ok, cmd} -> handle_command(cmd, state)
      {:error, _} -> {error("invalid JSON"), state}
    end
  end

  defp ok(data), do: %{status: "ok", data: data}
  defp error(message), do: %{status: "error", message: message}
end
