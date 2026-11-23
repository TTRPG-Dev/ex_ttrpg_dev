defmodule ExTTRPGDev.RuleSystems do
  @moduledoc """
  Public API for interacting with rule systems.

  Every rule system is loaded from one store (`ExTTRPGDev.RuleSystem.Store`),
  whatever its origin:

  - **Bundled** systems ship in the library under `priv/system_configs/`.
    They are releases that get installed into the store, by
    `sync_bundled/0` or lazily the first time an uninstalled bundled slug
    is loaded, and are stored non-modifiable.
  - **Local** systems are user-authored (or cloned) systems in the store.
    With the default filesystem store these are directories of TOML files
    under `local_system_configs/`, each with a `module.toml` manifest.

  Bundled and local systems share one slug namespace. If a local system
  already holds a bundled system's slug, the local system wins: the
  bundled release is skipped (with a logged warning) rather than
  overwriting or shadowing it. Rename or clone the local system to
  receive the bundled one.
  """

  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.Characters.{Character, Metadata}
  alias ExTTRPGDev.RuleSystem.{Graph, Loader, Store, Versioning}
  alias ExTTRPGDev.RuleSystems.{Bundled, LoadedSystem, Sync}

  @doc """
  Lists all available systems: everything installed in the store, plus
  bundled systems not yet installed (they install on first load).

  ## Examples
      iex> ExTTRPGDev.RuleSystems.list_systems() |> Enum.member?("dnd_5e_srd")
      true

  """
  def list_systems do
    list_bundled_systems!() ++ list_local_systems!()
  end

  @doc """
  Fetches all available systems: bundled systems first, then any other
  installed systems.

  Returns `{:ok, [slug, ...]}`, or `{:error, reason}` if the bundled
  systems or the store cannot be listed.
  """
  def fetch_systems do
    with {:ok, bundled} <- fetch_bundled_systems(),
         {:ok, entries} <- Store.adapter().list_entries() do
      installed = entries |> Enum.map(& &1.slug) |> Enum.uniq()
      {:ok, bundled ++ (installed -- bundled)}
    end
  end

  @doc """
  Fetches bundled systems shipped with the library.

  Returns `{:ok, [slug, ...]}`, or `{:error, reason}` if the bundled
  systems directory exists but cannot be listed.
  """
  def fetch_bundled_systems, do: Bundled.list()

  @doc """
  Lists bundled systems shipped with the library, raising on failure.

  See `fetch_bundled_systems/0` for the non-raising variant.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.list_bundled_systems!() |> Enum.member?("dnd_5e_srd")
      true

  """
  def list_bundled_systems! do
    case fetch_bundled_systems() do
      {:ok, slugs} -> slugs
      {:error, reason} -> raise "Failed to list bundled systems: #{inspect(reason)}"
    end
  end

  @doc false
  @deprecated "Use list_bundled_systems!/0 instead; this always could raise despite no bang"
  def list_bundled_systems, do: list_bundled_systems!()

  @doc """
  Fetches local systems: installed systems that aren't canonical content,
  i.e. user-authored systems and clones.

  Returns `{:ok, [slug, ...]}`, or `{:error, reason}` if the store cannot
  be listed.
  """
  def fetch_local_systems do
    with {:ok, entries} <- Store.adapter().list_entries() do
      {:ok,
       entries
       |> Enum.filter(&is_nil(&1.library_requirement))
       |> Enum.map(& &1.slug)
       |> Enum.uniq()}
    end
  end

  @doc """
  Lists user-defined local systems, raising on failure.

  See `fetch_local_systems/0` for the non-raising variant.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.list_local_systems!() |> is_list()
      true

  """
  def list_local_systems! do
    case fetch_local_systems() do
      {:ok, slugs} -> slugs
      {:error, reason} -> raise "Failed to list local systems: #{inspect(reason)}"
    end
  end

  @doc false
  @deprecated "Use list_local_systems!/0 instead; this always could raise despite no bang"
  def list_local_systems, do: list_local_systems!()

  @doc """
  Returns true if the system is a bundled system.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.bundled_system?("dnd_5e_srd")
      true

      iex> ExTTRPGDev.RuleSystems.bundled_system?("non_existent_system")
      false

  """
  def bundled_system?(system) when is_bitstring(system) do
    Enum.any?(list_bundled_systems!(), &(&1 == system))
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
    Enum.any?(list_local_systems!(), &(&1 == system))
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
  Returns the filesystem path to the given system's source directory: the
  bundled copy under `priv/system_configs/` for a bundled slug, otherwise
  the flat directory a local system has (or would have) in the default
  filesystem store. Systems are not *loaded* from this path; they're
  loaded from the store.

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
  Installs, updates, or replaces bundled systems in the store, per the
  rules in `ExTTRPGDev.RuleSystems.Replacement`, logging every decision.

  This is the only operation that replaces installed content; loading a
  system never does. Hosts call it deliberately, e.g. at boot or as a
  release step. See `ExTTRPGDev.RuleSystems.Sync`.

  Returns `{:ok, [{slug, result}, ...]}` or `{:error, reason}`.
  """
  defdelegate sync_bundled(), to: ExTTRPGDev.RuleSystems.Sync, as: :sync_all

  @doc """
  Loads, parses, and validates a rule system by slug.

  Without a `version`, loads the newest installed version. With one,
  loads the newest installed version on that version's release line (see
  `ExTTRPGDev.RuleSystem.Versioning.same_release_line?/2`): a non-breaking
  update replaces content in place, so asking for 1.1.0 after 1.2.0 was
  installed loads 1.2.0. A local system (user-authored or cloned) has a
  single version and is loaded whatever `version` is given.

  If the slug is a bundled system with nothing installed, it's installed
  first (see `sync_bundled/0`). Loading never replaces installed content.

  Returns `{:ok, %LoadedSystem{}}` containing the parsed module, validated
  DAG, and all supporting data needed for evaluation, or `{:error, reason}`
  (`{:not_configured, slug}` for an unknown slug,
  `{:version_not_installed, slug, version}` when nothing on the requested
  release line is installed).

  ## Examples
      iex> {:ok, system} = ExTTRPGDev.RuleSystems.load_system("dnd_5e_srd")
      iex> is_struct(system, ExTTRPGDev.RuleSystems.LoadedSystem)
      true

  """
  def load_system(system, version \\ nil) when is_bitstring(system) do
    store = Store.adapter()

    with :ok <- Sync.seed_if_absent(system),
         {:ok, entries} <- store.list_entries(),
         {:ok, entry} <- select_entry(entries, system, version),
         {:ok, source} <- store.fetch(entry.slug, entry.version),
         {:ok, loader_data} <- Loader.load_source(source),
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

  # Picks the installed entry to load for a slug. A non-canonical entry
  # (local or clone) wins if one holds the slug, matching the collision
  # policy, whatever version was asked for: it's the only version there is.
  # Otherwise, the newest canonical version on the requested version's
  # release line, or the newest overall when no version is requested.
  defp select_entry(entries, slug, version) do
    {canonical, local} =
      entries
      |> Enum.filter(&(&1.slug == slug))
      |> Enum.split_with(&(not is_nil(&1.library_requirement)))

    case {local, canonical} do
      {[entry | _], _} -> {:ok, entry}
      {[], []} -> {:error, {:not_configured, slug}}
      {[], installed} -> select_canonical(installed, slug, version)
    end
  end

  defp select_canonical(installed, _slug, nil), do: {:ok, newest(installed)}

  defp select_canonical(installed, slug, version) do
    case Enum.filter(installed, &Versioning.same_release_line?(&1.version, version)) do
      [] -> {:error, {:version_not_installed, slug, version}}
      on_line -> {:ok, newest(on_line)}
    end
  end

  defp newest(entries), do: Enum.max_by(entries, & &1.version, Version)

  @doc """
  Loads, parses, and validates a rule system by slug, raising on failure.

  See `load_system/1` for the non-raising variant.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.load_system!("dnd_5e_srd") |> is_struct(ExTTRPGDev.RuleSystems.LoadedSystem)
      true

  """
  def load_system!(system, version \\ nil) when is_bitstring(system) do
    case load_system(system, version) do
      {:ok, loaded_system} ->
        loaded_system

      {:error, reason} ->
        raise "Failed to load rule system #{system}: #{inspect(reason)}"
    end
  end

  @doc """
  Loads the rule system a character was built with, at the version it
  recorded (see `load_system/2`). A character saved before versions were
  recorded loads the newest installed version.

  Returns `{:ok, %LoadedSystem{}}` or `{:error, reason}`.
  """
  def load_system_for(%Character{metadata: %Metadata{} = metadata}) do
    load_system(metadata.rule_system, metadata.rule_system_version)
  end

  @doc """
  Loads the rule system a character was built with, raising on failure.

  See `load_system_for/1` for the non-raising variant.
  """
  def load_system_for!(%Character{metadata: %Metadata{} = metadata}) do
    load_system!(metadata.rule_system, metadata.rule_system_version)
  end
end
