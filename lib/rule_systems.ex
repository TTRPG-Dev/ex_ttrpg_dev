defmodule ExTTRPGDev.RuleSystems do
  @moduledoc """
  Public API for interacting with rule systems.

  Rule systems are defined as directories of TOML files under `priv/system_configs/`
  (bundled) or `local_system_configs/` (user-defined). Each system directory must
  contain a `package.toml` manifest.
  """

  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.RuleSystem.{Graph, Loader}
  alias ExTTRPGDev.RuleSystems.LoadedSystem

  @doc """
  Lists all available systems (bundled + local).

  ## Examples
      iex> ExTTRPGDev.RuleSystems.list_systems() |> Enum.member?("dnd_5e_srd")
      true

  """
  def list_systems do
    list_bundled_systems() ++ list_local_systems()
  end

  @doc """
  Lists bundled systems shipped with the library.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.list_bundled_systems() |> Enum.member?("dnd_5e_srd")
      true

  """
  def list_bundled_systems do
    base = Globals.system_configs_path()

    File.ls!(base)
    |> Enum.filter(fn name ->
      File.dir?(Path.join(base, name)) and
        File.exists?(Path.join([base, name, "package.toml"]))
    end)
  end

  @doc """
  Lists user-defined local systems.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.list_local_systems() |> is_list()
      true

  """
  def list_local_systems do
    base = Globals.local_system_configs_path()

    if File.exists?(base) do
      File.ls!(base)
      |> Enum.filter(fn name ->
        File.dir?(Path.join(base, name)) and
          File.exists?(Path.join([base, name, "package.toml"]))
      end)
    else
      []
    end
  end

  @doc """
  Returns true if the system is a bundled system.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.is_bundled_system?("dnd_5e_srd")
      true

      iex> ExTTRPGDev.RuleSystems.is_bundled_system?("non_existent_system")
      false

  """
  def is_bundled_system?(system) when is_bitstring(system) do
    Enum.any?(list_bundled_systems(), &(&1 == system))
  end

  @doc """
  Returns true if the system is a user-defined local system.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.is_local_system?("dnd_5e_srd")
      false

      iex> ExTTRPGDev.RuleSystems.is_local_system?("non_existent_system")
      false

  """
  def is_local_system?(system) when is_bitstring(system) do
    Enum.any?(list_local_systems(), &(&1 == system))
  end

  @doc """
  Returns true if the system is configured (bundled or local).

  ## Examples
      iex> ExTTRPGDev.RuleSystems.is_configured?("dnd_5e_srd")
      true

      iex> ExTTRPGDev.RuleSystems.is_configured?("non_existent_system")
      false
  """
  def is_configured?(system) when is_bitstring(system) do
    Enum.any?(list_systems(), &(&1 == system))
  end

  @doc """
  Ensures a system is configured, returning the slug if so, raising if not.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.assert_configured!("dnd_5e_srd")
      "dnd_5e_srd"

      iex> ExTTRPGDev.RuleSystems.assert_configured!("not_configured")
      ** (RuntimeError) System `not_configured` is not configured
  """
  def assert_configured!(system) when is_bitstring(system) do
    if is_configured?(system) do
      system
    else
      raise "System `#{system}` is not configured"
    end
  end

  @doc """
  Returns the filesystem path to the given system's directory.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.system_path!("dnd_5e_srd") |> String.ends_with?("dnd_5e_srd")
      true

  """
  def system_path!(system) when is_bitstring(system) do
    if is_bundled_system?(system) do
      Path.join(Globals.system_configs_path(), system)
    else
      Path.join(Globals.local_system_configs_path(), system)
    end
  end

  @doc """
  Loads, parses, and validates a rule system by slug.

  Returns a `%LoadedSystem{}` containing the parsed package, validated DAG,
  and all supporting data needed for evaluation.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.load_system!("dnd_5e_srd") |> is_struct(ExTTRPGDev.RuleSystems.LoadedSystem)
      true

  """
  def load_system!(system) when is_bitstring(system) do
    path = system_path!(system)
    loader_data = Loader.load!(path)

    case Graph.build(loader_data) do
      {:ok, system_map} ->
        %LoadedSystem{
          package: loader_data.package,
          graph: system_map.graph,
          nodes: system_map.nodes,
          rolling_methods: loader_data.rolling_methods,
          concept_metadata: loader_data.concept_metadata,
          contributions: loader_data.contributions
        }

      {:error, reason} ->
        raise "Failed to build rule system graph for #{system}: #{inspect(reason)}"
    end
  end
end
