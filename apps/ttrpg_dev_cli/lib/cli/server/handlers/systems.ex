defmodule ExTTRPGDev.CLI.Server.Handlers.Systems do
  @moduledoc """
  Handles the `systems.*` commands: listing, inspecting, and deleting rule
  systems.
  """

  alias ExTTRPGDev.CLI.Serializer
  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.Dependents

  def handle(%{"command" => "systems.list"}, state) do
    {:ok, %{systems: RuleSystems.list_systems()}, state}
  end

  def handle(%{"command" => "systems.show", "system" => slug} = cmd, state) do
    concept_type = Map.get(cmd, "concept_type")
    concept_id = Map.get(cmd, "concept_id")

    system = RuleSystems.load_system!(slug)

    data =
      cond do
        concept_id != nil ->
          meta = system.concept_metadata[{concept_type, concept_id}] || %{}
          %{id: concept_id, concept_type: concept_type, fields: meta}

        concept_type != nil ->
          Serializer.serialize_concepts(system, concept_type)

        true ->
          Serializer.serialize_system(system)
      end

    {:ok, data, state}
  end

  def handle(%{"command" => "systems.delete", "system" => slug}, state) do
    case RuleSystems.delete_system(slug) do
      # The engine always uses the default filesystem store, where a
      # deletable (local) system lives flat at {root}/{slug}.
      :ok ->
        {:ok, %{deleted: slug, path: Path.join(Globals.local_system_configs_path(), slug)}, state}

      {:error, reason} ->
        {:error, delete_error_message(slug, reason)}
    end
  end

  def handle(%{"command" => cmd}, _state),
    do: {:error, "invalid arguments for command: #{inspect(cmd)}"}

  defp delete_error_message(slug, :not_modifiable),
    do: "rule system #{inspect(slug)} is not modifiable (bundled systems can't be deleted)"

  defp delete_error_message(slug, {:not_configured, _}),
    do: "rule system not found: #{inspect(slug)}"

  defp delete_error_message(slug, {:has_dependents, found}) do
    {characters, others} = Enum.split_with(found, &match?({Dependents, _}, &1))

    parts =
      [
        characters != [] &&
          "#{length(characters)} saved character(s) use it: " <>
            Enum.map_join(characters, ", ", &elem(&1, 1)),
        others != [] && "also used by: " <> Enum.map_join(others, ", ", &inspect(elem(&1, 1)))
      ]
      |> Enum.filter(& &1)

    "cannot delete rule system #{inspect(slug)}: #{Enum.join(parts, "; ")}. " <>
      "Delete or move what uses it first."
  end

  defp delete_error_message(slug, {:dependents_unavailable, {_, {:unreadable_characters, bad}}}) do
    "cannot delete rule system #{inspect(slug)}: couldn't check which characters use it, " <>
      "because these character files can't be read: " <> Enum.map_join(bad, ", ", &elem(&1, 0))
  end

  defp delete_error_message(slug, reason),
    do: "cannot delete rule system #{inspect(slug)}: #{inspect(reason)}"
end
