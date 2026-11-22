defmodule ExTTRPGDev.RuleSystems do
  @moduledoc """
  Public API for interacting with rule systems.

  Rule systems are defined as directories of TOML files under `priv/system_configs/`
  (bundled) or `local_system_configs/` (user-defined). Each system directory must
  contain a `module.toml` manifest.
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
        File.exists?(Path.join([base, name, "module.toml"]))
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
          File.exists?(Path.join([base, name, "module.toml"]))
      end)
    else
      []
    end
  end

  @doc """
  Returns true if the system is a bundled system.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.bundled_system?("dnd_5e_srd")
      true

      iex> ExTTRPGDev.RuleSystems.bundled_system?("non_existent_system")
      false

  """
  def bundled_system?(system) when is_bitstring(system) do
    Enum.any?(list_bundled_systems(), &(&1 == system))
  end

  @doc false
  @deprecated "Use bundled_system?/1 instead; the is_ prefix is reserved for guards"
  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_bundled_system?(system), do: bundled_system?(system)

  @doc """
  Returns true if the system is a user-defined local system.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.local_system?("dnd_5e_srd")
      false

      iex> ExTTRPGDev.RuleSystems.local_system?("non_existent_system")
      false

  """
  def local_system?(system) when is_bitstring(system) do
    Enum.any?(list_local_systems(), &(&1 == system))
  end

  @doc false
  @deprecated "Use local_system?/1 instead; the is_ prefix is reserved for guards"
  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_local_system?(system), do: local_system?(system)

  @doc """
  Returns true if the system is configured (bundled or local).

  ## Examples
      iex> ExTTRPGDev.RuleSystems.configured?("dnd_5e_srd")
      true

      iex> ExTTRPGDev.RuleSystems.configured?("non_existent_system")
      false
  """
  def configured?(system) when is_bitstring(system) do
    Enum.any?(list_systems(), &(&1 == system))
  end

  @doc false
  @deprecated "Use configured?/1 instead; the is_ prefix is reserved for guards"
  # credo:disable-for-next-line Credo.Check.Readability.PredicateFunctionNames
  def is_configured?(system), do: configured?(system)

  @doc """
  Ensures a system is configured, returning the slug if so, raising if not.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.assert_configured!("dnd_5e_srd")
      "dnd_5e_srd"

      iex> ExTTRPGDev.RuleSystems.assert_configured!("not_configured")
      ** (RuntimeError) System `not_configured` is not configured
  """
  def assert_configured!(system) when is_bitstring(system) do
    if configured?(system) do
      system
    else
      raise "System `#{system}` is not configured"
    end
  end

  @doc """
  Returns the filesystem path to the given system's directory.

  Never raises: an unconfigured slug still yields a (non-existent) path
  under the local systems directory, since this is also used to build the
  path a new local system would be created at.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.system_path("dnd_5e_srd") |> String.ends_with?("dnd_5e_srd")
      true

  """
  def system_path(system) when is_bitstring(system) do
    if bundled_system?(system) do
      Path.join(Globals.system_configs_path(), system)
    else
      Path.join(Globals.local_system_configs_path(), system)
    end
  end

  @doc false
  @deprecated "Use system_path/1 instead; it never raised despite the bang"
  def system_path!(system), do: system_path(system)

  @doc """
  Loads, parses, and validates a rule system by slug.

  Returns `{:ok, %LoadedSystem{}}` containing the parsed module, validated
  DAG, and all supporting data needed for evaluation, or `{:error, reason}`.

  ## Examples
      iex> {:ok, system} = ExTTRPGDev.RuleSystems.load_system("dnd_5e_srd")
      iex> is_struct(system, ExTTRPGDev.RuleSystems.LoadedSystem)
      true

  """
  def load_system(system) when is_bitstring(system) do
    path = system_path(system)

    with {:ok, loader_data} <- Loader.load(path),
         {:ok, system_map} <- Graph.build(loader_data) do
      {:ok,
       %LoadedSystem{
         module: loader_data.module,
         graph: system_map.graph,
         nodes: system_map.nodes,
         rolling_methods: loader_data.rolling_methods,
         concept_metadata: loader_data.concept_metadata,
         effects: loader_data.effects,
         inventory_rules: loader_data.inventory_rules
       }}
    end
  end

  @doc """
  Loads, parses, and validates a rule system by slug, raising on failure.

  See `load_system/1` for the non-raising variant.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.load_system!("dnd_5e_srd") |> is_struct(ExTTRPGDev.RuleSystems.LoadedSystem)
      true

  """
  def load_system!(system) when is_bitstring(system) do
    case load_system(system) do
      {:ok, loaded_system} ->
        loaded_system

      {:error, reason} ->
        raise "Failed to load rule system #{system}: #{inspect(reason)}"
    end
  end
end
