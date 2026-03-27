defmodule ExTTRPGDev.RuleSystem.RuleModule do
  @moduledoc """
  Represents the parsed contents of a rule system's `module.toml` manifest.
  """

  defmodule ConceptType do
    @moduledoc "A declared concept type within a rule system module."
    defstruct [:id, :name, :display_template]
  end

  defmodule CharacterChoice do
    @moduledoc """
    A top-level concept selection a character must make during creation,
    e.g. choosing a race or class.
    """
    defstruct [:concept_type, required: true]
  end

  defmodule CharacterListCategory do
    @moduledoc """
    Defines one named list of character attributes for display, e.g. "Languages" or "Skills".

    `metadata_key` is the concept-metadata key whose values are collected.
    `concept_type`, when set, names the type used to look up display names for those values.
    `choice_concept_type`, when set, also collects character-decision selections of that type.
    """
    defstruct [:label, :metadata_key, :concept_type, :choice_concept_type]
  end

  defmodule DisplayConfig do
    @moduledoc "System-level display hints, e.g. which numeric fields show an explicit + sign."
    defstruct signed_fields: []
  end

  defmodule LabelFilter do
    @moduledoc """
    Maps a human-readable label string to a metadata filter used during
    metadata contribution expansion.

    When a value in a contribution source field matches `label`, the loader
    finds target concepts by checking `filter_field == filter_value` in their
    metadata rather than matching by name or concept ID.
    """
    defstruct [:label, :filter_field, :filter_value]
  end

  defmodule MetadataContribution do
    @moduledoc """
    Declares that string values in a metadata list field on one concept type
    should generate effects targeting matching concepts of another type.

    At load time the loader expands each `from_type` concept's `from_field`
    list into effects on matching `to_type` concepts, contributing `value` to
    their `to_field` accumulator node. Matching is done by `label_filters`
    first (category labels → metadata filter), then by concept name or ID.
    """
    defstruct [:from_type, :from_field, :to_type, :to_field, :value, label_filters: []]
  end

  defstruct [
    :name,
    :slug,
    :version,
    :family,
    :series,
    :publisher,
    :concept_types,
    :level_node,
    character_building_choices: [],
    character_lists: [],
    display_config: nil,
    metadata_contributions: []
  ]

  @required_keys ["name", "slug", "version"]

  @doc """
  Builds a RuleModule struct from a decoded TOML map.

  Returns `{:ok, %RuleModule{}}` on success or `{:error, reason}` on failure.
  """
  def from_map(%{"module" => module_map} = map) do
    missing = Enum.find(@required_keys, fn key -> not Map.has_key?(module_map, key) end)

    if missing do
      {:error, {:missing_required_key, missing}}
    else
      concept_types =
        map
        |> Map.get("concept_type", [])
        |> Enum.map(fn et ->
          %ConceptType{
            id: et["id"],
            name: et["name"],
            display_template: get_in(et, ["display", "template"])
          }
        end)

      character_lists =
        map
        |> Map.get("character_list", [])
        |> Enum.map(fn cl ->
          %CharacterListCategory{
            label: cl["label"],
            metadata_key: cl["metadata_key"],
            concept_type: cl["concept_type"],
            choice_concept_type: cl["choice_concept_type"]
          }
        end)

      display_config =
        case Map.get(map, "display") do
          nil -> %DisplayConfig{}
          dc -> %DisplayConfig{signed_fields: Map.get(dc, "signed_fields", [])}
        end

      metadata_contributions =
        map
        |> Map.get("metadata_contributions", [])
        |> Enum.map(&parse_metadata_contribution/1)

      {:ok,
       %__MODULE__{
         name: module_map["name"],
         slug: module_map["slug"],
         version: module_map["version"],
         family: module_map["family"],
         series: module_map["series"],
         publisher: module_map["publisher"],
         level_node: module_map["level_node"],
         concept_types: concept_types,
         character_lists: character_lists,
         display_config: display_config,
         metadata_contributions: metadata_contributions
       }}
    end
  end

  def from_map(_), do: {:error, {:missing_required_key, "module"}}

  defp parse_metadata_contribution(mc) do
    label_filters =
      mc
      |> Map.get("label_filters", [])
      |> Enum.map(fn lf ->
        %LabelFilter{
          label: lf["label"],
          filter_field: lf["filter_field"],
          filter_value: lf["filter_value"]
        }
      end)

    %MetadataContribution{
      from_type: mc["from_type"],
      from_field: mc["from_field"],
      to_type: mc["to_type"],
      to_field: mc["to_field"],
      value: mc["value"],
      label_filters: label_filters
    }
  end

  @doc """
  Returns a MapSet of declared concept type id strings.
  """
  def concept_type_ids(%__MODULE__{concept_types: concept_types}) do
    concept_types
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end
end
