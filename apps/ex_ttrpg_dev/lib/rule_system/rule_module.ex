defmodule ExTTRPGDev.RuleSystem.RuleModule do
  @moduledoc """
  Represents the parsed contents of a rule system's `module.toml` manifest.

  ## Versioning keys

  Two `[module]` keys describe how a system's content is versioned:

  - `"version"` *(string, required)* — the system's own content version (its
    `rule_system_version`), bumped on the system's own cadence rather than
    the library's. A change that could invalidate saved character data
    (renaming or removing a concept, node, or effect target) bumps its
    breaking component; purely additive content does not.
  - `"library_requirement"` *(string, optional)* — a Hex/SemVer requirement
    (e.g. `"~> 0.15.0"`) naming the library releases this content's structure
    is compatible with. Only canonical content maintained alongside the
    library declares it. When present, `"version"` must be valid SemVer so
    that releases can be compared.

  ## Class levels

  - `"class_concept_type"` *(string, optional)* — the concept type whose
    concepts are classes a character levels in. Setting it enables class
    levels: each concept of the type gets a `level` node (e.g.
    `class('fighter').level`), and a character's total level is split among
    its classes. Must name a declared concept type that is also a
    `character_choice` in `character_building.toml` (a character's first
    class is its creation choice), and requires `"level_node"`, which stays
    the character's total level.
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
    :library_requirement,
    :family,
    :series,
    :publisher,
    :concept_types,
    :level_node,
    :class_concept_type,
    character_building_choices: [],
    character_lists: [],
    display_config: nil,
    metadata_contributions: [],
    custom_metadata_keys: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          slug: String.t(),
          version: String.t(),
          library_requirement: String.t() | nil,
          family: String.t() | nil,
          series: String.t() | nil,
          publisher: String.t() | nil,
          concept_types: [%ConceptType{}],
          level_node: String.t() | nil,
          class_concept_type: String.t() | nil,
          character_building_choices: [%CharacterChoice{}],
          character_lists: [%CharacterListCategory{}],
          display_config: %DisplayConfig{} | nil,
          metadata_contributions: [%MetadataContribution{}],
          custom_metadata_keys: [String.t()]
        }

  @required_keys ["name", "slug", "version"]

  @doc """
  Builds a RuleModule struct from a decoded TOML map.

  Returns `{:ok, %RuleModule{}}` on success or `{:error, reason}` on failure.
  """
  def from_map(%{"module" => module_map} = map) do
    concept_types_raw = Map.get(map, "concept_type", [])
    metadata_contributions_raw = Map.get(map, "metadata_contributions", [])

    with :ok <- validate_required_keys(module_map),
         :ok <- validate_versioning(module_map),
         :ok <- validate_concept_types(concept_types_raw),
         :ok <- validate_class_concept_type(module_map, concept_types_raw),
         :ok <- validate_metadata_contributions(metadata_contributions_raw) do
      {:ok,
       %__MODULE__{
         name: module_map["name"],
         slug: module_map["slug"],
         version: module_map["version"],
         library_requirement: module_map["library_requirement"],
         family: module_map["family"],
         series: module_map["series"],
         publisher: module_map["publisher"],
         level_node: module_map["level_node"],
         class_concept_type: module_map["class_concept_type"],
         concept_types: parse_concept_types(concept_types_raw),
         character_lists: parse_character_lists(map),
         display_config: parse_display_config(map),
         metadata_contributions: parse_metadata_contributions(metadata_contributions_raw),
         custom_metadata_keys: Map.get(module_map, "custom_metadata_keys", [])
       }}
    end
  end

  def from_map(_), do: {:error, {:missing_required_key, "module"}}

  defp validate_required_keys(module_map) do
    case Enum.find(@required_keys, &(not Map.has_key?(module_map, &1))) do
      nil -> :ok
      missing -> {:error, {:missing_required_key, missing}}
    end
  end

  # A system that declares no library_requirement isn't canonical content, so
  # its "version" is free-form and never compared. One that does must have a
  # parseable requirement and a SemVer "version", or replacement decisions
  # couldn't be made for it.
  defp validate_versioning(%{"library_requirement" => nil}), do: :ok

  defp validate_versioning(%{"library_requirement" => requirement, "version" => version}) do
    with :ok <- validate_library_requirement(requirement) do
      validate_semver(version)
    end
  end

  defp validate_versioning(_module_map), do: :ok

  defp validate_library_requirement(requirement) when is_binary(requirement) do
    case Version.parse_requirement(requirement) do
      {:ok, _} -> :ok
      :error -> {:error, {:invalid_library_requirement, requirement}}
    end
  end

  defp validate_library_requirement(requirement),
    do: {:error, {:invalid_library_requirement, requirement}}

  defp validate_semver(version) when is_binary(version) do
    case Version.parse(version) do
      {:ok, _} -> :ok
      :error -> {:error, {:invalid_rule_system_version, version}}
    end
  end

  defp validate_semver(version), do: {:error, {:invalid_rule_system_version, version}}

  defp parse_concept_types(concept_types_raw) do
    Enum.map(concept_types_raw, fn et ->
      %ConceptType{
        id: et["id"],
        name: et["name"],
        display_template: get_in(et, ["display", "template"])
      }
    end)
  end

  defp parse_character_lists(map) do
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
  end

  defp parse_display_config(map) do
    case Map.get(map, "display") do
      nil -> %DisplayConfig{}
      dc -> %DisplayConfig{signed_fields: Map.get(dc, "signed_fields", [])}
    end
  end

  defp parse_metadata_contributions(list) do
    Enum.map(list, &parse_metadata_contribution/1)
  end

  defp validate_concept_types(list) do
    case Enum.find_index(list, fn et -> is_nil(et["id"]) end) do
      nil -> :ok
      idx -> {:error, {:concept_type_missing_id, idx}}
    end
  end

  # Class levels split the total level among classes, so a system enabling
  # them must say where the total level comes from.
  defp validate_class_concept_type(%{"class_concept_type" => nil}, _concept_types), do: :ok

  defp validate_class_concept_type(%{"class_concept_type" => type_id} = module_map, concept_types) do
    cond do
      not Enum.any?(concept_types, &(&1["id"] == type_id)) ->
        {:error, {:unknown_class_concept_type, type_id}}

      is_nil(module_map["level_node"]) ->
        {:error, {:class_concept_type_requires_level_node, type_id}}

      true ->
        :ok
    end
  end

  defp validate_class_concept_type(_module_map, _concept_types), do: :ok

  defp validate_metadata_contributions(list) do
    list
    |> Enum.with_index()
    |> Enum.find_value(:ok, &check_metadata_contribution_fields/1)
  end

  defp check_metadata_contribution_fields({mc, idx}) do
    required = ~w(from_type from_field to_type to_field value)

    case Enum.find(required, &is_nil(mc[&1])) do
      nil -> nil
      field -> {:error, {:metadata_contribution_missing_field, field, idx}}
    end
  end

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
