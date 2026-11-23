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
  The default adapter is `ExTTRPGDev.RuleSystem.Store.FileSystem`.
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

  @doc "Lists every installed entry, across all slugs and versions."
  @callback list_entries() :: {:ok, [Entry.t()]} | {:error, term()}

  @doc "Fetches the content of one installed entry."
  @callback fetch(slug :: String.t(), version :: String.t() | nil) ::
              {:ok, Source.t()} | {:error, :not_found} | {:error, term()}

  @doc """
  Stores `source` as `entry`. With `overwrite` false, fails with
  `{:error, :already_exists}` if that `{slug, version}` is installed;
  with `overwrite` true, replaces it. Must be all-or-nothing: a failed or
  concurrent put never leaves a partially written entry visible.
  """
  @callback put(entry :: Entry.t(), source :: Source.t(), overwrite :: boolean()) ::
              :ok | {:error, :already_exists} | {:error, term()}

  @doc "Removes one installed entry."
  @callback delete(slug :: String.t(), version :: String.t() | nil) ::
              :ok | {:error, :not_found} | {:error, term()}
end
