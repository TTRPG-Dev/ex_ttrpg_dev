defmodule ExTTRPGDev.RuleSystems.Replacement do
  @moduledoc """
  Decides whether a release of canonical rule system content may be applied
  to a store that may already hold versions of the same system.

  The store is multi-version: several content versions of one slug can be
  installed at once, so that a breaking release never strands characters
  (or host records) built against an older one. This module is pure
  decision-making; it changes nothing. Applying a plan is the store's job,
  and is only ever done through an explicit sync a host calls deliberately,
  never implicitly on load.

  ## The decision, in order

  1. **Exemptions.** Only canonical content (see
     `ExTTRPGDev.RuleSystem.Versioning.canonical?/1`) is ever applied
     automatically. If the slug is already held by non-canonical content
     (a user-authored system or a clone), that content wins and the release
     is skipped. A slug collision is never resolved by overwriting or
     shadowing local content.
  2. **Hard gate: library compliance.** If the running library doesn't
     satisfy the release's `library_requirement`, it is blocked outright:
     the loader may not understand its structure.
  3. **Soft gate: dependents × breaking-ness.**
     - Nothing installed: install.
     - An installed version is on the release's line (a non-breaking
       bump): replace it in place. Its dependents keep working, now
       against the newer content.
     - The release is a breaking change from every installed version:
       install it alongside them. Each older version with no dependents
       is removed; each with dependents is retained and reported, since
       those dependents need explicit migration.
     - The release is already installed, or is older than what's installed
       on its line, or older than everything installed with no line of its
       own: skip.
  """

  require Logger

  alias ExTTRPGDev.RuleSystem.{RuleModule, Versioning}
  alias ExTTRPGDev.RuleSystems.Dependents

  @typedoc """
  What applying a release should do. `install` is the release's version;
  `remove` are installed versions it supersedes; `retain` are older
  versions kept because something still depends on them.
  """
  @type plan :: %{
          install: String.t(),
          remove: [String.t()],
          retain: [{String.t(), [Dependents.t()]}]
        }

  @type skip_reason ::
          :not_canonical
          | {:slug_taken, String.t()}
          | {:already_installed, String.t()}
          | {:superseded_by, String.t()}

  @type decision ::
          {:apply, plan()}
          | {:skip, skip_reason()}
          | {:blocked, {:library_requirement, String.t(), String.t()}}
          | {:error, term()}

  @doc """
  Decides how `release` should be applied given the `installed` versions of
  the same system.

  Options:

  - `:library_version` — the library version the hard gate checks against.
    Defaults to the running library.
  - `:dependents` — a `(slug, version -> {:ok, [dependent]} | {:error, term})`
    function. Defaults to `ExTTRPGDev.RuleSystems.Dependents.find/2`.

  Returns a `t:decision/0`. A dependents lookup failure is returned as
  `{:error, reason}` and never treated as "no dependents".
  """
  @spec decide([RuleModule.t()], RuleModule.t(), keyword()) :: decision()
  def decide(installed, %RuleModule{} = release, opts \\ []) do
    library_version = Keyword.get(opts, :library_version, Versioning.library_version())
    dependents = Keyword.get(opts, :dependents, &Dependents.find/2)

    with :ok <- check_exemptions(installed, release),
         :ok <- check_library(release, library_version) do
      plan(installed, release, dependents)
    end
  end

  defp check_exemptions(installed, release) do
    cond do
      not Versioning.canonical?(release) ->
        {:skip, :not_canonical}

      local = Enum.find(installed, &(not Versioning.canonical?(&1))) ->
        {:skip, {:slug_taken, local.version}}

      true ->
        :ok
    end
  end

  defp check_library(release, library_version) do
    if Versioning.library_compatible?(release, library_version) do
      :ok
    else
      {:blocked, {:library_requirement, release.library_requirement, library_version}}
    end
  end

  defp plan([], release, _dependents) do
    {:apply, %{install: release.version, remove: [], retain: []}}
  end

  defp plan(installed, release, dependents) do
    versions = Enum.map(installed, & &1.version)

    case Enum.find(versions, &Versioning.same_release_line?(&1, release.version)) do
      nil -> plan_breaking(versions, release, dependents)
      line_version -> plan_in_line(line_version, release)
    end
  end

  defp plan_in_line(installed_version, release) do
    case Version.compare(release.version, installed_version) do
      :gt -> {:apply, %{install: release.version, remove: [installed_version], retain: []}}
      :eq -> {:skip, {:already_installed, installed_version}}
      :lt -> {:skip, {:superseded_by, installed_version}}
    end
  end

  defp plan_breaking(versions, release, dependents) do
    newest = Enum.max(versions, Version)

    if Version.compare(release.version, newest) == :lt do
      {:skip, {:superseded_by, newest}}
    else
      partition_by_dependents(versions, release, dependents)
    end
  end

  defp partition_by_dependents(versions, release, dependents) do
    versions
    |> Enum.reduce_while({:ok, [], []}, fn version, {:ok, remove, retain} ->
      case dependents.(release.slug, version) do
        {:ok, []} -> {:cont, {:ok, [version | remove], retain}}
        {:ok, found} -> {:cont, {:ok, remove, [{version, found} | retain]}}
        {:error, reason} -> {:halt, {:error, {:dependents, version, reason}}}
      end
    end)
    |> case do
      {:ok, remove, retain} ->
        {:apply,
         %{install: release.version, remove: Enum.reverse(remove), retain: Enum.reverse(retain)}}

      error ->
        error
    end
  end

  @doc """
  Logs a decision made by `decide/3` for `release`: `:info` when it
  changes the store, `:debug` when it's a no-op (already installed,
  superseded, not canonical) so routine syncs stay quiet, `:warning` when
  it leaves something for a human (blocked, slug taken, retained
  versions), and `:error` when dependents couldn't be determined. Returns
  the decision unchanged, so calls can be piped.
  """
  @spec log(decision(), RuleModule.t()) :: decision()
  def log(decision, %RuleModule{slug: slug, version: version} = release) do
    {level, message} = describe(decision, release)
    Logger.log(level, ~s("#{slug}" #{version}: #{message}))
    decision
  end

  defp describe({:apply, %{remove: remove, retain: []}}, _release) do
    {:info, "applying" <> removing(remove)}
  end

  defp describe({:apply, %{remove: remove, retain: retain}}, _release) do
    kept =
      Enum.map_join(retain, "; ", fn {version, found} ->
        "#{version} retained for #{length(found)} dependent(s)"
      end)

    {:warning,
     "applying alongside older versions" <>
       removing(remove) <> ". #{kept}; manual migration required"}
  end

  defp describe({:skip, :not_canonical}, _release) do
    {:debug, "not canonical content (no library_requirement); never applied automatically"}
  end

  defp describe({:skip, {:slug_taken, local_version}}, _release) do
    {:warning,
     "slug is held by non-canonical content (version #{local_version}); keeping it. " <>
       "Rename or clone it to receive canonical releases"}
  end

  defp describe({:skip, {:already_installed, _}}, _release), do: {:debug, "already installed"}

  defp describe({:skip, {:superseded_by, newer}}, _release) do
    {:debug, "older than installed #{newer}; skipping"}
  end

  defp describe({:blocked, {:library_requirement, requirement, running}}, _release) do
    {:warning,
     ~s(library_requirement "#{requirement}" NOT satisfied by running #{running}; ) <>
       "not applying, library upgrade required first"}
  end

  defp describe({:error, reason}, _release) do
    {:error, "could not determine dependents (#{inspect(reason)}); not applying"}
  end

  defp removing([]), do: ""
  defp removing(versions), do: ", replacing #{Enum.join(versions, ", ")}"
end
