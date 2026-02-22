defmodule ExTTRPGDev.RuleSystem.RuleModule do
  @moduledoc """
  Represents the parsed contents of a rule system's `module.toml` manifest.
  """

  defmodule ConceptType do
    @moduledoc "A declared concept type within a rule system module."
    defstruct [:id, :name]
  end

  defstruct [:name, :slug, :version, :family, :series, :publisher, :concept_types]

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
        |> Enum.map(fn et -> %ConceptType{id: et["id"], name: et["name"]} end)

      {:ok,
       %__MODULE__{
         name: module_map["name"],
         slug: module_map["slug"],
         version: module_map["version"],
         family: module_map["family"],
         series: module_map["series"],
         publisher: module_map["publisher"],
         concept_types: concept_types
       }}
    end
  end

  def from_map(_), do: {:error, {:missing_required_key, "module"}}

  @doc """
  Returns a MapSet of declared concept type id strings.
  """
  def concept_type_ids(%__MODULE__{concept_types: concept_types}) do
    concept_types
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end
end
