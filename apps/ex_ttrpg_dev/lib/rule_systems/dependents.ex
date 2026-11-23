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
    Enum.reduce_while(sources(), {:ok, []}, fn source, {:ok, acc} ->
      case source.dependents(rule_system, version) do
        {:ok, found} -> {:cont, {:ok, acc ++ Enum.map(found, &{source, &1})}}
        {:error, reason} -> {:halt, {:error, {source, reason}}}
      end
    end)
  end
end
