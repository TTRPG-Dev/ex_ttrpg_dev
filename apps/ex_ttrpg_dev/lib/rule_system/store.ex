defmodule ExTTRPGDev.RuleSystem.Store do
  @moduledoc """
  Where rule system content lives: a behaviour for storage adapters.

  A store holds *entries*, each one version of one system, addressed by
  `{slug, version}`. Several versions of the same slug can be installed at
  once, so that a breaking release of canonical content never strands
  characters built against an older one (see
  `ExTTRPGDev.RuleSystems.Replacement`).

  Each entry carries its metadata (`ExTTRPGDev.RuleSystem.Store.Entry`)
  alongside its content (`ExTTRPGDev.RuleSystem.Source`), so listing what's
  installed never requires decoding a system's concepts.

  Adapters are deliberately simple storage: they don't decide what may be
  installed, replaced, or modified. Those policies (the replacement gates,
  `is_modifiable` enforcement, clone semantics, slug collisions) live in
  `ExTTRPGDev.RuleSystems` and apply identically whichever adapter is used.

  ## Choosing an adapter

  The default adapter is `ExTTRPGDev.RuleSystem.Store.FileSystem`, which
  keeps each entry as a directory of TOML files. A host application that
  keeps rule systems elsewhere (e.g. a database) implements this behaviour
  and names its module in config:

      # config/config.exs
      config :ex_ttrpg_dev, :rule_system_store, MyApp.RuleSystemStore

      defmodule MyApp.RuleSystemStore do
        @behaviour ExTTRPGDev.RuleSystem.Store

        alias ExTTRPGDev.RuleSystem.Source
        alias ExTTRPGDev.RuleSystem.Store.Entry

        @impl true
        def list_entries, do: # {:ok, [%Entry{}, ...]}, without decoding content

        @impl true
        def fetch(slug, version), do: # {:ok, %Source{}} | {:error, :not_found}

        @impl true
        def put(%Entry{} = entry, %Source{} = source, overwrite) do
          # Store both atomically under {entry.slug, entry.version};
          # {:error, :already_exists} if present and overwrite is false.
        end

        @impl true
        def delete(slug, version), do: # :ok | {:error, :not_found}
      end

  The configured adapter is the only store: bundled systems are seeded
  into it (see `ExTTRPGDev.RuleSystems.sync_bundled/0`) just like into the
  filesystem store, so a host adapter holds the library's canonical
  content as well as its own. A `Source` is already-decoded data, so an
  adapter never parses TOML; a system with no `character_building` or
  `inventory_rules` simply has `nil` there.

  An adapter may file each version of a slug separately, or keep a single
  version per slug and replace it in place (as the filesystem adapter does
  for non-canonical systems); `ExTTRPGDev.RuleSystems` handles both.

  The adapter is read at call time, so it can be changed while the
  application is running (tests do this). Character persistence is
  pluggable the same way, through `ExTTRPGDev.Characters.Store` and the
  `:characters_store` key (#164).
  """

  alias ExTTRPGDev.RuleSystem.Source

  defmodule Entry do
    @moduledoc """
    Stored metadata for one installed version of a rule system.

    - `slug`, `version` — the entry's address. `version` is the content
      version from `module.toml`; it is `nil` only if the adapter couldn't
      read one (e.g. a hand-edited `module.toml` that fails to decode).
    - `library_requirement` — copied from `module.toml`; present only on
      canonical content.
    - `is_modifiable` — when `false`, the system must not be edited in
      place; changes go to a clone under a new slug instead. Independent
      of `library_requirement`: a host may lock its own content too.
    """
    defstruct [:slug, :version, :library_requirement, is_modifiable: true]

    @type t :: %__MODULE__{
            slug: String.t(),
            version: String.t() | nil,
            library_requirement: String.t() | nil,
            is_modifiable: boolean()
          }

    @doc """
    Builds the entry describing `source`, with the given `is_modifiable`.

    ## Examples
        iex> source = %ExTTRPGDev.RuleSystem.Source{module: %{"module" => %{"slug" => "s", "version" => "1.0.0"}}}
        iex> ExTTRPGDev.RuleSystem.Store.Entry.from_source(source, false)
        %ExTTRPGDev.RuleSystem.Store.Entry{slug: "s", version: "1.0.0", library_requirement: nil, is_modifiable: false}

    """
    @spec from_source(Source.t(), boolean()) :: t()
    def from_source(%Source{module: %{"module" => module}}, is_modifiable) do
      %__MODULE__{
        slug: module["slug"],
        version: module["version"],
        library_requirement: module["library_requirement"],
        is_modifiable: is_modifiable
      }
    end
  end

  @doc """
  The store adapter in use: the module configured under
  `:rule_system_store`, defaulting to
  `ExTTRPGDev.RuleSystem.Store.FileSystem`.

  ## Examples
      iex> ExTTRPGDev.RuleSystem.Store.adapter()
      ExTTRPGDev.RuleSystem.Store.FileSystem

  """
  @spec adapter() :: module()
  def adapter do
    Application.get_env(:ex_ttrpg_dev, :rule_system_store, ExTTRPGDev.RuleSystem.Store.FileSystem)
  end

  @doc "Lists every installed entry, across all slugs and versions."
  @callback list_entries() :: {:ok, [Entry.t()]} | {:error, term()}

  @doc "Fetches the content of one installed entry."
  @callback fetch(slug :: String.t(), version :: String.t() | nil) ::
              {:ok, Source.t()} | {:error, :not_found} | {:error, term()}

  @doc """
  Stores `source` as `entry`. Must be all-or-nothing: a failed or
  concurrent put never leaves a partially written entry visible.

  With `overwrite` false, fails with `{:error, :already_exists}` if
  anything already occupies the place the entry would be stored: an
  installed `{slug, version}`, *or* anything else there that
  `list_entries/0` doesn't report (e.g. leftover or half-written data).
  The occupant must be left untouched. The library tells the two cases
  apart by listing again, so `:already_exists` should be returned for
  both, not a different error.

  With `overwrite` true, replaces an installed entry.
  """
  @callback put(entry :: Entry.t(), source :: Source.t(), overwrite :: boolean()) ::
              :ok | {:error, :already_exists} | {:error, term()}

  @doc "Removes one installed entry."
  @callback delete(slug :: String.t(), version :: String.t() | nil) ::
              :ok | {:error, :not_found} | {:error, term()}
end
