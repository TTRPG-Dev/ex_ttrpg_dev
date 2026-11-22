defmodule ExTTRPGDev.Characters.Character do
  alias __MODULE__
  alias DiceLib.Basic, as: Dice
  alias ExTTRPGDev.Characters.{Decision, InventoryItem, Metadata}
  alias ExTTRPGDev.RuleSystem.Effect
  alias ExTTRPGDev.RuleSystem.InventoryRules
  alias ExTTRPGDev.RuleSystem.Node
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @moduledoc """
  Definition of an individual character.

  - `generated_values` — map of `{type_id, concept_id, field_name} => integer` for leaf nodes
  - `effects` — list of `%Effect{target: {type_id, concept_id, field_name}, value: integer}`
    for currently active items, feats, statuses etc. (defaults to [])
  - `decisions` — list of `%Decision{scope: nil | {type_id, concept_id}, choice: string, selection: string}`
    recording each concept selection made during character creation (defaults to [])
  - `inventory` — list of `%InventoryItem{}` representing items the character is carrying
    (defaults to [])
  - `pending_choice_slots` — list of `%{progression_id: string, earned_at_level: integer, max_level_cap: integer}`
    tracking unresolved selection slots with the max concept level available when they were earned
    (defaults to [])
  """
  @type t :: %__MODULE__{}
  defstruct [
    :name,
    :generated_values,
    :metadata,
    effects: [],
    decisions: [],
    inventory: [],
    pending_choice_slots: []
  ]

  @doc """
  Generates a character for the given loaded rule system.
  Rolls dice for all generated nodes using the system's rolling methods.
  Accepts a list of decisions representing concept selections made during character creation.

  If any chosen concepts (race, class, background, etc.) declare `starting_equipment`,
  those items are automatically added to the character's inventory with default field values
  from the system's inventory schema.

  Raises if any starting-equipment spec in the chosen concepts' config is malformed
  (see `inventory_from_decisions/2`) — character generation reads system config that
  is expected to already be valid, same as an unknown rolling method.
  """
  def gen_character!(%LoadedSystem{} = system, decisions \\ []) do
    character_name = Faker.Person.name()

    generated_values =
      system.nodes
      |> Enum.filter(fn {_key, node} -> node.type == :generated end)
      |> Map.new(fn {node_key, node} ->
        {node_key, roll_generated_value(node, system.rolling_methods)}
      end)

    {:ok, %{items: starting_inventory, errors: errors}} =
      inventory_from_decisions(decisions, system)

    if errors != [] do
      raise "invalid starting-equipment spec(s): #{inspect(errors)}"
    end

    %Character{
      name: character_name,
      generated_values: generated_values,
      effects: [],
      decisions: decisions,
      inventory: starting_inventory,
      metadata: %Metadata{
        slug: slugify(character_name),
        rule_system: system.module.slug
      }
    }
  end

  @doc """
  Encodes the character to a JSON-serializable map.
  Tuple keys in `generated_values` are encoded as `"type:id:field"` strings.
  Decision scopes are encoded as `null` (for nil) or `"type:id"` strings.
  """
  def to_json_map(%Character{} = char) do
    %{
      "name" => char.name,
      "generated_values" =>
        Map.new(char.generated_values, fn {{type, id, field}, value} ->
          {"#{type}:#{id}:#{field}", value}
        end),
      "effects" =>
        Enum.map(char.effects, fn %Effect{target: {type, id, field}, value: v} ->
          %{"target" => "#{type}:#{id}:#{field}", "value" => v}
        end),
      "inventory" =>
        Enum.map(char.inventory, fn %InventoryItem{} = item ->
          %{
            "concept_type" => item.concept_type,
            "concept_id" => item.concept_id,
            "fields" => item.fields
          }
        end),
      "decisions" => Enum.map(char.decisions, &Decision.to_json_map/1),
      "pending_choice_slots" =>
        Enum.map(char.pending_choice_slots, fn %{
                                                 progression_id: pid,
                                                 earned_at_level: level,
                                                 max_level_cap: cap
                                               } ->
          %{"progression_id" => pid, "earned_at_level" => level, "max_level_cap" => cap}
        end),
      "metadata" => %{
        "slug" => char.metadata.slug,
        "rule_system" => char.metadata.rule_system
      }
    }
  end

  @doc """
  Deserializes a character from its JSON string representation.

  Returns `{:ok, character}`, or `{:error, {:invalid_character_data, message}}`
  if `json` is malformed or doesn't match the expected character shape.
  """
  def from_json(json) when is_bitstring(json) do
    {:ok, parse_json!(json)}
  rescue
    e -> {:error, {:invalid_character_data, Exception.message(e)}}
  end

  @doc """
  Deserializes a character from its JSON string representation, raising on
  failure.

  See `from_json/1` for the non-raising variant.
  """
  def from_json!(json) when is_bitstring(json) do
    case from_json(json) do
      {:ok, character} -> character
      {:error, reason} -> raise "Failed to parse character JSON: #{inspect(reason)}"
    end
  end

  defp parse_json!(json) do
    map = Poison.decode!(json)

    generated_values =
      Map.new(map["generated_values"] || %{}, fn {key, value} ->
        [type, id, field] = String.split(key, ":", parts: 3)
        {{type, id, field}, value}
      end)

    effects =
      Enum.map(map["effects"] || [], fn %{"target" => target, "value" => v} ->
        [type, id, field] = String.split(target, ":", parts: 3)
        %Effect{target: {type, id, field}, value: v}
      end)

    inventory =
      Enum.map(map["inventory"] || [], fn item ->
        %InventoryItem{
          concept_type: item["concept_type"],
          concept_id: item["concept_id"],
          fields: item["fields"] || %{}
        }
      end)

    decisions = Enum.map(map["decisions"] || [], &Decision.from_json_map/1)

    pending_choice_slots =
      Enum.map(map["pending_choice_slots"] || [], fn slot ->
        %{
          progression_id: slot["progression_id"],
          earned_at_level: slot["earned_at_level"],
          max_level_cap: slot["max_level_cap"]
        }
      end)

    %Character{
      name: map["name"],
      generated_values: generated_values,
      effects: effects,
      inventory: inventory,
      decisions: decisions,
      pending_choice_slots: pending_choice_slots,
      metadata: %Metadata{
        slug: map["metadata"]["slug"],
        rule_system: map["metadata"]["rule_system"]
      }
    }
  end

  @doc """
  Computes the inventory items granted by a character's decisions: static
  `starting_equipment` on chosen concepts, plus items from equipment-choice
  sub-choices (`grants_to = "inventory"`).

  Returns `{:ok, %{items: items, errors: errors}}`. `errors` reports a
  starting-equipment spec that was malformed — missing `"type"`/`"id"`, or
  failing inventory-item validation for a reason other than
  `{:not_inventoriable, _}` (declaring equipment for a type the system
  doesn't configure as inventoriable is intentional, not a mistake, and is
  silently skipped). Each entry is `%{spec: spec, reason: reason}`. A
  malformed spec contributes no item, but every other spec still resolves
  normally.
  """
  def inventory_from_decisions(decisions, system) do
    {static_items, static_errors} = starting_equipment_items(decisions, system)
    {chosen_items, chosen_errors} = equipment_choice_items(decisions, system)

    {:ok, %{items: static_items ++ chosen_items, errors: static_errors ++ chosen_errors}}
  end

  defp starting_equipment_items(decisions, system) do
    decisions
    |> Enum.filter(&(&1.scope == nil))
    |> Enum.reduce({[], []}, fn %{choice: type, selection: id}, {items_acc, errors_acc} ->
      specs =
        system.concept_metadata
        |> Map.get({type, id}, %{})
        |> Map.get("starting_equipment", [])

      {items, errors} = items_from_specs(specs, system.inventory_rules)
      {items_acc ++ items, errors_acc ++ errors}
    end)
  end

  defp equipment_choice_items(decisions, system) do
    Enum.reduce(decisions, {[], []}, fn decision, {items_acc, errors_acc} ->
      case equipment_choice_spec(decision, system) do
        nil ->
          {items_acc, errors_acc}

        spec ->
          {items, errors} = items_from_specs([spec], system.inventory_rules)
          {items_acc ++ items, errors_acc ++ errors}
      end
    end)
  end

  defp equipment_choice_spec(
         %Decision{scope: {type, id}, choice: choice_id, selection: selected},
         system
       ) do
    choice_def =
      system.concept_metadata
      |> Map.get({type, id}, %{})
      |> Map.get("choices", %{})
      |> Map.get(choice_id, %{})

    if Map.get(choice_def, "grants_to") == "inventory" do
      %{"type" => choice_def["type"], "id" => selected}
    end
  end

  defp equipment_choice_spec(_decision, _system), do: nil

  defp items_from_specs(specs, inventory_rules) do
    Enum.reduce(specs, {[], []}, fn spec, {items_acc, errors_acc} ->
      case item_from_spec(spec, inventory_rules) do
        {:ok, item} -> {items_acc ++ [item], errors_acc}
        :skip -> {items_acc, errors_acc}
        {:error, reason} -> {items_acc, errors_acc ++ [%{spec: spec, reason: reason}]}
      end
    end)
  end

  defp item_from_spec(%{"type" => type, "id" => id} = spec, %InventoryRules{} = inventory_rules) do
    custom_fields = Map.get(spec, "fields", %{})

    case InventoryItem.new(type, id, inventory_rules, custom_fields) do
      {:ok, item} -> {:ok, item}
      # Not every starting-equipment entry needs to be inventory-tracked
      # (e.g. a type the system declares but never configures as inventoriable).
      {:error, {:not_inventoriable, _type}} -> :skip
      {:error, reason} -> {:error, reason}
    end
  end

  defp item_from_spec(_spec, _inventory_rules), do: {:error, :missing_type_or_id}

  defp roll_generated_value(%Node{method: method_id}, rolling_methods) do
    method = resolve_rolling_method(method_id, rolling_methods)
    rolls = Dice.roll(method.dice)

    rolls =
      if method.drop == "lowest" do
        rolls |> Enum.sort() |> tl()
      else
        rolls
      end

    Enum.sum(rolls)
  end

  defp resolve_rolling_method(nil, rolling_methods) do
    case Enum.find(rolling_methods, fn {_id, method} -> method.default end) do
      {_id, method} ->
        method

      nil ->
        raise "generated node has no rolling method and no rolling method declares " <>
                "default = true; set one or add an explicit \"method\" to the node"
    end
  end

  defp resolve_rolling_method(method_id, rolling_methods) do
    Map.get(rolling_methods, method_id) ||
      raise "unknown rolling method #{inspect(method_id)}"
  end

  @doc """
  Converts a character name into its canonical slug.

  This is the single definition of the slug rules — any caller that derives
  a slug from a name (e.g. frontends creating characters) must use it, or
  characters saved under one slug become unfindable under another.

  ## Examples

      iex> ExTTRPGDev.Characters.Character.slugify("Mr. Whiskers")
      "mr_whiskers"

      iex> ExTTRPGDev.Characters.Character.slugify("D'Artagnan the Bold")
      "dartagnan_the_bold"

  """
  def slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[!#$%&()*+,.:;<=>?@\^_`'{|}~-]/, "")
    |> String.replace(" ", "_")
  end
end
