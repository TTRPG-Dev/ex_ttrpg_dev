defmodule ExTTRPGDev.CLI.Server.Handlers.Inventory do
  @moduledoc """
  Handles the `characters.inventory*`, `characters.spells`, and
  `characters.activate` commands: typed inventory management and
  preparation/activation state.
  """

  alias ExTTRPGDev.Characters
  alias ExTTRPGDev.Characters.InventoryItem
  alias ExTTRPGDev.CLI.Serializer
  alias ExTTRPGDev.CLI.Server.Errors
  alias ExTTRPGDev.RuleSystem.InventoryRules
  alias ExTTRPGDev.RuleSystems

  def handle(%{"command" => "characters.inventory", "character" => slug}, state) do
    character = Characters.load_character!(slug)
    {:ok, %{inventory: Serializer.serialize_inventory(character.inventory)}, state}
  end

  def handle(
        %{
          "command" => "characters.inventory.add",
          "character" => slug,
          "type" => type,
          "id" => id
        } =
          cmd,
        state
      ) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)
    custom_fields = Map.get(cmd, "fields", %{})

    case InventoryItem.new(type, id, system.inventory_rules, custom_fields) do
      {:ok, item} ->
        updated = %{character | inventory: character.inventory ++ [item]}
        Characters.save_character!(updated, true)
        {:ok, %{inventory: Serializer.serialize_inventory(updated.inventory)}, state}

      {:error, reason} ->
        {:error, "cannot add item: " <> Errors.message(reason)}
    end
  end

  def handle(
        %{
          "command" => "characters.inventory.set",
          "character" => slug,
          "index" => index,
          "field" => field,
          "value" => value
        },
        state
      ) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)

    item =
      Enum.at(character.inventory, index) ||
        raise("no inventory item at index #{inspect(index)}")

    case InventoryItem.set_field(item, field, value, system.inventory_rules) do
      {:ok, updated_item} ->
        new_inventory = List.replace_at(character.inventory, index, updated_item)
        updated = %{character | inventory: new_inventory}
        Characters.save_character!(updated, true)
        {:ok, %{inventory: Serializer.serialize_inventory(updated.inventory)}, state}

      {:error, reason} ->
        {:error, "cannot set field: " <> Errors.message(reason)}
    end
  end

  def handle(%{"command" => "characters.spells", "character" => slug}, state) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)

    # Only the first preparation type is returned. Returning multiple types
    # would require a protocol change on both this handler and the Rust
    # PreparationStateResponse struct. dnd_5e_srd has one preparation type
    # ("spell"), so this is sufficient for now.
    result =
      case InventoryRules.preparation_types(system.inventory_rules) do
        [] ->
          {:ok, %{preparation_mode: nil}}

        [{type_id, _} | _] ->
          case Characters.preparation_state(system, character, type_id) do
            {:ok, %{mode: nil}} -> {:ok, %{preparation_mode: nil}}
            {:ok, s} -> {:ok, format_prep_response(s)}
            error -> error
          end
      end

    case result do
      {:ok, data} -> {:ok, data, state}
      {:error, reason} -> {:error, Errors.message(reason)}
    end
  end

  def handle(
        %{
          "command" => "characters.activate",
          "character" => slug,
          "verb" => verb,
          "items" => item_ids
        },
        state
      ) do
    character = Characters.load_character!(slug)
    system = RuleSystems.load_system!(character.metadata.rule_system)

    case InventoryRules.type_for_activate_command(system.inventory_rules, verb) do
      nil ->
        {:error, "unknown activate verb: #{inspect(verb)}"}

      {type_id, _config} ->
        case Characters.activate(system, character, type_id, item_ids) do
          {:ok, updated} ->
            Characters.save_character!(updated, true)
            {:ok, %{inventory: Serializer.serialize_inventory(updated.inventory)}, state}

          {:error, reason} ->
            {:error, Errors.message(reason)}
        end
    end
  end

  def handle(%{"command" => cmd}, _state),
    do: {:error, "invalid arguments for command: #{inspect(cmd)}"}

  defp format_prep_response(%{
         mode: mode,
         cap: cap,
         eligible: eligible,
         always_prepared: always,
         prepared: prepared
       }) do
    base = %{
      preparation_mode: mode,
      eligible_items: eligible,
      prepared_items: prepared,
      always_active: always
    }

    if cap, do: Map.put(base, :cap, cap), else: base
  end
end
