defmodule ExTTRPGDev.RuleSystems.Dependents do
  @moduledoc """
  Reports what depends on a given version of a rule system, so that a
  breaking update is never allowed to replace content something still
  relies on.

  The library knows about its own dependents: saved characters (see
  `ExTTRPGDev.Characters.characters_depending_on/2`), which are always
  consulted. A host application can have dependents the library can't see,
  e.g. its own records that reference a rule system. To report those,
  implement this behaviour and list the module in application config:

      # config/config.exs
      config :ex_ttrpg_dev, :rule_system_dependents, [MyApp.CampaignDependents]

      defmodule MyApp.CampaignDependents do
        @behaviour ExTTRPGDev.RuleSystems.Dependents

        @impl true
        def dependents(rule_system, version) do
          {:ok, MyApp.Campaigns.ids_using(rule_system, version)}
        end
      end

  A dependent may be any term meaningful to the host; it's only reported
  back, never interpreted. "Depends on a version" should follow the same
  rule the library uses for characters: same release line (see
  `ExTTRPGDev.RuleSystem.Versioning.same_release_line?/2`), since a
  non-breaking update replaces a version in place.
  """

  alias ExTTRPGDev.Characters

  @typedoc "A dependent, tagged with the module that reported it."
  @type t :: {module(), term()}

  @doc """
  Returns what depends on `version` of `rule_system`, or `{:error, reason}`
  if dependents couldn't be determined. Returning an error blocks a breaking
  replacement, so an implementation that can't be sure should error rather
  than return `{:ok, []}`.
  """
  @callback dependents(rule_system :: String.t(), version :: String.t()) ::
              {:ok, [term()]} | {:error, term()}

  @behaviour __MODULE__

  @doc """
  The library's own implementation: saved characters, reported by slug.
  """
  @impl true
  def dependents(rule_system, version) do
    Characters.characters_depending_on(rule_system, version)
  end

  @doc """
  The modules consulted by `find/2`: this module first, then any configured
  under `:rule_system_dependents`.
  """
  @spec sources() :: [module()]
  def sources do
    [__MODULE__ | Application.get_env(:ex_ttrpg_dev, :rule_system_dependents, [])]
  end

  @doc """
  Collects dependents of `version` of `rule_system` from every source in
  `sources/0`.

  Returns `{:ok, [{module, dependent}, ...]}`, or
  `{:error, {module, reason}}` from the first source that fails.
  """
  @spec find(String.t(), String.t()) :: {:ok, [t()]} | {:error, {module(), term()}}
  def find(rule_system, version) do
    sources()
    |> Enum.map(&{&1, fn -> &1.dependents(rule_system, version) end})
    |> collect()
  end

  @doc false
  # Used by RuleSystems.delete_system/1: what depends on the system as a
  # whole. Saved characters match at any version (a local system serves
  # every version asked of it; see Characters.characters_depending_on/1).
  # Host sources, whose contract is per version, are asked about each of
  # `versions`. Same result shape as find/2, without duplicates.
  @spec find_any_version(String.t(), [String.t()]) ::
          {:ok, [t()]} | {:error, {module(), term()}}
  def find_any_version(rule_system, versions) do
    own = {__MODULE__, fn -> Characters.characters_depending_on(rule_system) end}

    hosts =
      for source <- sources() -- [__MODULE__], version <- versions do
        {source, fn -> source.dependents(rule_system, version) end}
      end

    with {:ok, found} <- collect([own | hosts]), do: {:ok, Enum.uniq(found)}
  end

  # Runs each `{source, query}` in order, tagging what each finds with its
  # source; stops at the first failure.
  defp collect(queries) do
    Enum.reduce_while(queries, {:ok, []}, fn {source, query}, {:ok, acc} ->
      case query.() do
        {:ok, found} -> {:cont, {:ok, acc ++ Enum.map(found, &{source, &1})}}
        {:error, reason} -> {:halt, {:error, {source, reason}}}
      end
    end)
  end
end
