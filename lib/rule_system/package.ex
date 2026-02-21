defmodule ExTTRPGDev.RuleSystem.Package do
  @moduledoc """
  Represents the parsed contents of a rule system's `package.toml` manifest.
  """

  defmodule EntityType do
    @moduledoc "A declared entity type within a rule system package."
    defstruct [:id, :name]
  end

  defstruct [:name, :slug, :version, :family, :series, :publisher, :entity_types]

  @required_keys ["name", "slug", "version"]

  @doc """
  Builds a Package struct from a decoded TOML map.

  Returns `{:ok, %Package{}}` on success or `{:error, reason}` on failure.
  """
  def from_map(%{"package" => package_map} = map) do
    missing = Enum.find(@required_keys, fn key -> not Map.has_key?(package_map, key) end)

    if missing do
      {:error, {:missing_required_key, missing}}
    else
      entity_types =
        map
        |> Map.get("entity_type", [])
        |> Enum.map(fn et -> %EntityType{id: et["id"], name: et["name"]} end)

      {:ok,
       %__MODULE__{
         name: package_map["name"],
         slug: package_map["slug"],
         version: package_map["version"],
         family: package_map["family"],
         series: package_map["series"],
         publisher: package_map["publisher"],
         entity_types: entity_types
       }}
    end
  end

  def from_map(_), do: {:error, {:missing_required_key, "package"}}

  @doc """
  Returns a MapSet of declared entity type id strings.
  """
  def entity_type_ids(%__MODULE__{entity_types: entity_types}) do
    entity_types
    |> Enum.map(& &1.id)
    |> MapSet.new()
  end
end
