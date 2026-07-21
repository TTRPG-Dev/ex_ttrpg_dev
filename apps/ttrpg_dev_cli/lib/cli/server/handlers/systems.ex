defmodule ExTTRPGDev.CLI.Server.Handlers.Systems do
  @moduledoc """
  Handles the `systems.*` commands: listing and inspecting rule systems.
  """

  alias ExTTRPGDev.CLI.Serializer
  alias ExTTRPGDev.RuleSystems

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

  def handle(%{"command" => cmd}, _state),
    do: {:error, "invalid arguments for command: #{inspect(cmd)}"}
end
