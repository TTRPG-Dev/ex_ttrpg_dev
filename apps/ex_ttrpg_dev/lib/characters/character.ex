defmodule ExTTRPGDev.Characters.Character do
  alias __MODULE__
  alias ExTTRPGDev.Characters.{InventoryItem, Metadata}
  alias ExTTRPGDev.Dice
  alias ExTTRPGDev.RuleSystem.InventoryRules
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @moduledoc """
  Definition of an individual character.

  - `generated_values` — map of `{type_id, concept_id, field_name} => integer` for leaf nodes
  - `effects` — list of `%{target: {type_id, concept_id, field_name}, value: integer}`
    for currently active items, feats, statuses etc. (defaults to [])
  - `decisions` — list of `%{scope: nil | {type_id, concept_id}, choice: string, selection: string}`
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
  """
  def gen_character!(%LoadedSystem{} = system, decisions \\ []) do
    character_name = Faker.Person.name()

    generated_values =
      system.nodes
      |> Enum.filter(fn {_key, node} -> node.type == :generated end)
      |> Map.new(fn {node_key, node} ->
        {node_key, roll_generated_value(node, system.rolling_methods)}
      end)

    starting_inventory = inventory_from_decisions(decisions, system)

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
        Enum.map(char.effects, fn %{target: {type, id, field}, value: v} ->
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
      "decisions" => Enum.map(char.decisions, &serialize_decision/1),
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
  """
  def from_json!(json) when is_bitstring(json) do
    map = Poison.decode!(json)

    generated_values =
      Map.new(map["generated_values"] || %{}, fn {key, value} ->
        [type, id, field] = String.split(key, ":", parts: 3)
        {{type, id, field}, value}
      end)

    effects =
      Enum.map(map["effects"] || [], fn %{"target" => target, "value" => v} ->
        [type, id, field] = String.split(target, ":", parts: 3)
        %{target: {type, id, field}, value: v}
      end)

    inventory =
      Enum.map(map["inventory"] || [], fn item ->
        %InventoryItem{
          concept_type: item["concept_type"],
          concept_id: item["concept_id"],
          fields: item["fields"] || %{}
        }
      end)

    decisions = Enum.map(map["decisions"] || [], &deserialize_decision/1)

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

  defp serialize_decision(%{scope: nil, choice: choice, selection: selection}) do
    %{"scope" => nil, "choice" => choice, "selection" => selection}
  end

  defp serialize_decision(%{scope: {type, id}, choice: choice, selection: selection}) do
    %{"scope" => "#{type}:#{id}", "choice" => choice, "selection" => selection}
  end

  defp deserialize_decision(%{"scope" => nil, "choice" => choice, "selection" => selection}) do
    %{scope: nil, choice: choice, selection: selection}
  end

  defp deserialize_decision(%{"scope" => scope_str, "choice" => choice, "selection" => selection}) do
    [type, id] = String.split(scope_str, ":", parts: 2)
    %{scope: {type, id}, choice: choice, selection: selection}
  end

  def inventory_from_decisions(decisions, system) do
    static = starting_equipment_items(decisions, system)
    chosen = equipment_choice_items(decisions, system)
    static ++ chosen
  end

  defp starting_equipment_items(decisions, system) do
    decisions
    |> Enum.filter(&(&1.scope == nil))
    |> Enum.flat_map(fn %{choice: type, selection: id} ->
      system.concept_metadata
      |> Map.get({type, id}, %{})
      |> Map.get("starting_equipment", [])
      |> Enum.flat_map(&item_from_spec(&1, system.inventory_rules))
    end)
  end

  defp equipment_choice_items(decisions, system) do
    Enum.flat_map(decisions, fn
      %{scope: {type, id}, choice: choice_id, selection: selected} ->
        choice_def =
          system.concept_metadata
          |> Map.get({type, id}, %{})
          |> Map.get("choices", %{})
          |> Map.get(choice_id, %{})

        if Map.get(choice_def, "grants_to") == "inventory" do
          item_type = choice_def["type"]
          item_from_spec(%{"type" => item_type, "id" => selected}, system.inventory_rules)
        else
          []
        end

      _ ->
        []
    end)
  end

  defp item_from_spec(%{"type" => type, "id" => id} = spec, %InventoryRules{} = inventory_rules) do
    custom_fields = Map.get(spec, "fields", %{})

    case InventoryItem.new(type, id, inventory_rules, custom_fields) do
      {:ok, item} -> [item]
      _ -> []
    end
  end

  defp item_from_spec(_, _), do: []

  defp roll_generated_value(%{method: method_id}, rolling_methods) do
    method = Map.get(rolling_methods, method_id || "standard")
    rolls = Dice.roll(method.dice)

    rolls =
      if method.drop == "lowest" do
        rolls |> Enum.sort() |> tl()
      else
        rolls
      end

    Enum.sum(rolls)
  end

  defp slugify(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[!#$%&()*+,.:;<=>?@\^_`'{|}~-]/, "")
    |> String.replace(" ", "_")
  end
end
