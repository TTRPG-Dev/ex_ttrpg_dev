defmodule ExTTRPGDev.Characters.Character do
  alias __MODULE__
  alias ExTTRPGDev.Characters.Metadata
  alias ExTTRPGDev.Dice
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @moduledoc """
  Definition of an individual character.

  - `generated_values` — map of `{type_id, concept_id, field_name} => integer` for leaf nodes
  - `effects` — list of `%{target: {type_id, concept_id, field_name}, value: integer}`
    for currently active items, feats, statuses etc. (defaults to [])
  """
  defstruct [:name, :generated_values, :effects, :metadata]

  @doc """
  Generates a character for the given loaded rule system.
  Rolls dice for all generated nodes using the system's rolling methods.
  """
  def gen_character!(%LoadedSystem{} = system) do
    character_name = Faker.Person.name()

    generated_values =
      system.nodes
      |> Enum.filter(fn {_key, node} -> node.type == :generated end)
      |> Map.new(fn {node_key, node} ->
        {node_key, roll_generated_value(node, system.rolling_methods)}
      end)

    %Character{
      name: character_name,
      generated_values: generated_values,
      effects: [],
      metadata: %Metadata{
        slug: slugify(character_name),
        rule_system: system.package.slug
      }
    }
  end

  @doc """
  Encodes the character to a JSON-serializable map.
  Tuple keys in `generated_values` are encoded as `"type:id:field"` strings.
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

    %Character{
      name: map["name"],
      generated_values: generated_values,
      effects: effects,
      metadata: %Metadata{
        slug: map["metadata"]["slug"],
        rule_system: map["metadata"]["rule_system"]
      }
    }
  end

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
