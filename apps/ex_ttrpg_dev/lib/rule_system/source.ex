defmodule ExTTRPGDev.RuleSystem.Source do
  @moduledoc """
  A rule system's content as decoded data, independent of where it's stored.

  - `module` — the decoded `module.toml` map.
  - `character_building` — the decoded `character_building.toml` map, or
    `nil` if the system has none.
  - `inventory_rules` — the decoded `inventory_rules.toml` map, or `nil`.
  - `concepts` — `{name, map}` pairs, one per concept file, in a stable
    order. `name` is the file's path relative to the system root (e.g.
    `"concepts/abilities.toml"`), kept so content can be written back to the
    same layout and so errors can name the file.

  `ExTTRPGDev.RuleSystem.Loader.load_source/1` builds a system from a
  `Source`; nothing downstream of it cares where the data came from.
  """

  @module_file "module.toml"
  @character_building_file "character_building.toml"
  @inventory_rules_file "inventory_rules.toml"
  @concepts_glob "concepts/**/*.toml"

  defstruct [:module, character_building: nil, inventory_rules: nil, concepts: []]

  @type t :: %__MODULE__{
          module: map(),
          character_building: map() | nil,
          inventory_rules: map() | nil,
          concepts: [{String.t(), map()}]
        }

  @doc """
  Reads and decodes a rule system directory of TOML files.

  Only missing optional files (`character_building.toml`,
  `inventory_rules.toml`) fall back to `nil`; any other read or decode
  failure is returned as an error naming the file it came from.
  """
  @spec read(Path.t()) :: {:ok, t()} | {:error, term()}
  def read(path) do
    with {:ok, module} <- read_module(path),
         {:ok, character_building} <-
           read_optional(path, @character_building_file, :character_building_error),
         {:ok, inventory_rules} <-
           read_optional(path, @inventory_rules_file, :inventory_rules_error),
         {:ok, concepts} <- read_concepts(path) do
      {:ok,
       %__MODULE__{
         module: module,
         character_building: character_building,
         inventory_rules: inventory_rules,
         concepts: concepts
       }}
    end
  end

  defp read_module(path) do
    case read_toml(Path.join(path, @module_file)) do
      {:ok, map} -> {:ok, map}
      {:error, reason} -> {:error, {:module_parse_error, reason}}
    end
  end

  defp read_optional(path, file, error_tag) do
    case read_toml(Path.join(path, file)) do
      {:ok, map} -> {:ok, map}
      {:error, :enoent} -> {:ok, nil}
      {:error, reason} -> {:error, {error_tag, reason}}
    end
  end

  defp read_concepts(path) do
    path
    |> Path.join(@concepts_glob)
    |> Path.wildcard()
    |> Enum.sort()
    |> Enum.reduce_while({:ok, []}, fn file_path, {:ok, acc} ->
      case read_toml(file_path) do
        {:ok, map} -> {:cont, {:ok, [{Path.relative_to(file_path, path), map} | acc]}}
        {:error, reason} -> {:halt, {:error, {:file_parse_error, file_path, reason}}}
      end
    end)
    |> case do
      {:ok, concepts} -> {:ok, Enum.reverse(concepts)}
      error -> error
    end
  end

  defp read_toml(file_path) do
    with {:ok, contents} <- File.read(file_path) do
      TomlElixir.decode(contents)
    end
  end
end
