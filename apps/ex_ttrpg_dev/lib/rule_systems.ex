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
  alias ExTTRPGDev.RuleSystem.{Graph, Loader, Store}
  alias ExTTRPGDev.RuleSystems.{Bundled, Installed, LoadedSystem}

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
  Fetches every installed system version with its stored metadata, as
  `ExTTRPGDev.RuleSystem.Store.Entry` structs: `slug`, `version` (the
  system's own content version), `library_requirement` (canonical content
  only), and `is_modifiable`.

  Unlike `fetch_systems/0`, this only reports what is installed: a bundled
  system that hasn't been seeded yet isn't listed.

  Returns `{:ok, [%Entry{}, ...]}` or `{:error, reason}`.
  """
  def fetch_installed_systems, do: Store.adapter().list_entries()

  @doc """
  Lists every installed system version with its stored metadata, raising
  on failure. See `fetch_installed_systems/0`.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.load_system!("dnd_5e_srd")
      iex> ExTTRPGDev.RuleSystems.list_installed_systems!()
      ...> |> Enum.find(&(&1.slug == "dnd_5e_srd"))
      ...> |> then(&{&1.is_modifiable, is_binary(&1.library_requirement)})
      {false, true}

  """
  def list_installed_systems! do
    case fetch_installed_systems() do
      {:ok, entries} -> entries
      {:error, reason} -> raise "Failed to list installed systems: #{inspect(reason)}"
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
    with {:ok, _entry, source} <- Installed.resolve(system, version),
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

  @doc """
  Reads a rule system's `module.toml` metadata (name, slug, version,
  publisher, concept types, ...) without loading the rest of it.

  Unlike `load_system/2`, the concepts aren't parsed and no DAG is built,
  so this succeeds for a system whose content doesn't load yet, e.g. one
  being authored. `version` selects the installed version as for
  `load_system/2`, and a bundled system with nothing installed is
  installed first.

  Returns `{:ok, %RuleModule{}}`, or `{:error, reason}`:
  `{:not_configured, slug}` for an unknown slug,
  `{:version_not_installed, slug, version}` as for `load_system/2`, or
  `{:module_parse_error, reason}` if `module.toml` itself is invalid.

  ## Examples
      iex> {:ok, module} = ExTTRPGDev.RuleSystems.fetch_module("dnd_5e_srd")
      iex> module.slug
      "dnd_5e_srd"

  """
  def fetch_module(system, version \\ nil) when is_bitstring(system) do
    with {:ok, _entry, source} <- Installed.resolve(system, version) do
      Loader.build_module(source)
    end
  end

  @doc """
  Creates a new, empty local system from `[module]` metadata, ready for
  content (concept types, concepts, character lists) to be authored.

  `fields` is a map with string keys:

  - `"name"` *(required)* — display name.
  - `"slug"` *(optional)* — defaults to `slug_from_name/1` of the name. A
    given slug must already be in that form (lowercase letters and digits
    in any script, single underscores).
  - `"version"` *(optional)* — defaults to `"1.0.0"`. Free-form, as for
    any local system.
  - `"publisher"`, `"family"`, `"series"` *(optional)*.

  Values are trimmed; `nil` or blank optional values are omitted from the
  stored module rather than stored empty. The system is modifiable and has
  no `library_requirement`, so it's never replaced by `sync_bundled/0`.

  Returns `{:ok, slug}`, or `{:error, reason}`:

  - `{:slug_taken, slug}` if the slug is installed or is a bundled
    system's slug (as for `clone_system/3`).
  - `{:slug_occupied, slug}` if no listed system has the slug, but the
    store already holds something where it would be stored (with the
    default filesystem store, a `local_system_configs/{slug}` directory
    that isn't a listed system, e.g. one with no `module.toml`). It's left
    untouched. Also returned if the store can't be listed again to check.
  - `{:invalid_slug, slug}` if a given slug isn't in slug form, or the name
    yields an empty slug (it has no letters or digits).
  - `{:slug_too_long, slug, max_bytes}` if the slug (given or derived) is
    longer than `max_bytes` bytes of UTF-8, the most a store accepts.
  - `{:invalid_module, reason}` for a missing name, an unknown key, a
    non-string value, or a module that doesn't load.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.create_system(%{"name" => "SRD", "slug" => "dnd_5e_srd"})
      {:error, {:slug_taken, "dnd_5e_srd"}}

      iex> ExTTRPGDev.RuleSystems.create_system(%{"publisher" => "Acme Games"})
      {:error, {:invalid_module, {:missing_required_key, "name"}}}

  """
  defdelegate create_system(fields), to: ExTTRPGDev.RuleSystems.Editing

  @doc """
  Derives a system slug from a display name: NFC-normalized and
  lowercased, runs of whitespace and hyphens become one underscore,
  anything other than letters, combining marks, digits (in any script) and
  underscores is removed, repeated underscores are collapsed, and
  leading/trailing underscores trimmed.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.slug_from_name("My Fantasy System")
      "my_fantasy_system"

      iex> ExTTRPGDev.RuleSystems.slug_from_name("  Sci-Fi: Year 3000! ")
      "sci_fi_year_3000"

      iex> ExTTRPGDev.RuleSystems.slug_from_name("Über Regeln")
      "über_regeln"

      iex> ExTTRPGDev.RuleSystems.slug_from_name("ドラゴン 2")
      "ドラゴン_2"

  """
  defdelegate slug_from_name(name), to: ExTTRPGDev.RuleSystems.Editing

  @doc """
  Copies a system's full content (module, concepts, character-building and
  inventory-rules data) under `new_slug`, as a local system.

  The clone is modifiable and has no `library_requirement`, so it is never
  replaced by `sync_bundled/0`: cloning deliberately severs the link to
  the library's versioning. Its `version` is kept, as a record of what it
  was cloned from. This is how to change a non-modifiable system: clone
  it, then `update_system/2` the clone.

  Options:

  - `:version` — clone the installed version on this release line rather
    than the newest (see `load_system/2`).
  - `:name` — the clone's display name. Trimmed; when omitted, `nil` or
    blank, the clone keeps the source's name.

  `new_slug` must be in slug form, as a slug given to `create_system/1`
  must (lowercase letters and digits in any script, single underscores).

  Returns `{:ok, new_slug}`, or `{:error, reason}`:

  - `{:invalid_slug, new_slug}` if `new_slug` isn't a string in slug form.
  - `{:slug_too_long, new_slug, max_bytes}` if it's longer than
    `max_bytes` bytes of UTF-8.
  - `{:slug_taken, new_slug}` if it's installed or is a bundled system's
    slug.
  - `{:slug_occupied, new_slug}` if the store already holds something that
    isn't a system where it would go (see `create_system/1`).
  - `{:invalid_module, {:not_a_string, "name", name}}` if `:name` isn't a
    string.
  - any other reason if the source can't be resolved or the clone can't be
    stored.
  """
  defdelegate clone_system(source_slug, new_slug, opts \\ []), to: ExTTRPGDev.RuleSystems.Editing

  @doc """
  Edits an installed system in place: `update_fun` receives its current
  `ExTTRPGDev.RuleSystem.Source` and returns the new one.

  Only modifiable systems can be updated. A non-modifiable system (every
  seeded bundled system, or one a host has locked) fails with
  `{:error, {:not_modifiable, :clone_required}}` and is left untouched;
  `clone_system/3` it first and update the clone. The library never clones
  implicitly, so a caller can't end up editing a copy it didn't ask for.

  The update may change content and `version`, but not the `slug` or the
  `library_requirement`, and the result must load; otherwise
  `{:error, {:invalid_update, reason}}` and nothing is stored.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.update_system("dnd_5e_srd", & &1)
      {:error, {:not_modifiable, :clone_required}}

  Returns `:ok` or `{:error, reason}`.
  """
  defdelegate update_system(slug, update_fun), to: ExTTRPGDev.RuleSystems.Editing

  @doc """
  Declares a new concept type in a modifiable system's `module.toml`, so
  concepts of that type can be authored.

  `fields` is a map with string keys:

  - `"name"` *(required)* — display name. The type's ID is derived from
    it by `slug_from_name/1`.
  - `"display_template"` *(optional)* — stored as the type's
    `display.template`, e.g. `"{{name}} (Cost: {{cost}})"`.

  Values are trimmed; a `nil` or blank display template is omitted rather
  than stored empty. The new type is appended after the system's existing
  ones. This is an `update_system/2`, so the same rules apply: the system
  must be modifiable and must still load afterwards.

  Returns `{:ok, id}`, or `{:error, reason}`:

  - `{:concept_type_exists, id}` if the system already declares a type
    with the derived ID.
  - `{:invalid_concept_type_id, id}` if the derived ID can't be used in a
    formula (`type('concept').field`): it's empty (the name has no letters
    or digits) or has letters outside ASCII.
  - `{:invalid_concept_type, reason}` for a missing name, an unknown key,
    or a non-string value.
  - `{:not_configured, slug}`, `{:not_modifiable, :clone_required}` or
    `{:invalid_update, reason}`, as for `update_system/2`.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.add_concept_type("dnd_5e_srd", %{"name" => "Feat"})
      {:error, {:not_modifiable, :clone_required}}

      iex> ExTTRPGDev.RuleSystems.add_concept_type("dnd_5e_srd", %{"display_template" => "{{name}}"})
      {:error, {:invalid_concept_type, {:missing_required_key, "name"}}}

  """
  defdelegate add_concept_type(slug, fields), to: ExTTRPGDev.RuleSystems.Editing

  @doc """
  Removes a system from the store: every installed version of `slug`.

  Only modifiable systems can be deleted. A non-modifiable system (every
  seeded bundled system, or one a host has locked) fails with
  `{:error, :not_modifiable}` and is left untouched, as does a bundled
  slug that isn't installed yet: deleting a bundled system would achieve
  nothing, since `sync_bundled/0` seeds it again. A local system holding a
  bundled slug can be deleted; the bundled system is then seeded in its
  place the next time it's loaded or synced.

  Deletion is refused while anything depends on the system, so nothing is
  left referring to a system that no longer exists:

  - `{:error, {:has_dependents, [{module, dependent}, ...]}}` lists them,
    tagged as by `ExTTRPGDev.RuleSystems.Dependents.find/2`. Saved
    characters count whatever version they recorded (see
    `ExTTRPGDev.Characters.characters_depending_on/1`); host dependents are
    asked about each installed version.
  - `{:error, {:dependents_unavailable, {module, reason}}}` if dependents
    couldn't be determined (e.g. an unreadable character), which is never
    treated as "no dependents".

  Returns `:ok`, `{:error, {:not_configured, slug}}` for an unknown slug,
  or one of the errors above.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.delete_system("dnd_5e_srd")
      {:error, :not_modifiable}

      iex> ExTTRPGDev.RuleSystems.delete_system("non_existent_system")
      {:error, {:not_configured, "non_existent_system"}}

  """
  defdelegate delete_system(slug), to: ExTTRPGDev.RuleSystems.Editing

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
