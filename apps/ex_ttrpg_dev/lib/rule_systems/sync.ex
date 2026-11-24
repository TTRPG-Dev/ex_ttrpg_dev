defmodule ExTTRPGDev.RuleSystems.Sync do
  @moduledoc """
  Installs bundled rule system releases into the store, applying the
  decisions made by `ExTTRPGDev.RuleSystems.Replacement`.

  ## When this runs

  Replacing installed content is only ever done by an explicit call to
  `ExTTRPGDev.RuleSystems.sync_bundled/0`, which a host makes deliberately
  (at boot, or as a release step). Loading a system never replaces
  content: the only implicit action is seeding a bundled slug that has no
  installed version at all, which can't affect anything that already
  exists. This keeps long-running hosts free of mid-session content swaps.

  Every decision is logged (see `ExTTRPGDev.RuleSystems.Replacement.log/2`).
  """

  alias ExTTRPGDev.RuleSystem.{RuleModule, Store}
  alias ExTTRPGDev.RuleSystem.Store.Entry
  alias ExTTRPGDev.RuleSystems.{Bundled, Replacement}

  @type result :: Replacement.decision() | {:error, term()}

  @doc """
  Syncs every bundled system. Returns `{:ok, [{slug, result}, ...]}`, or
  `{:error, reason}` if the bundled systems or the store can't be listed.
  """
  @spec sync_all() :: {:ok, [{String.t(), result()}]} | {:error, term()}
  def sync_all do
    with {:ok, slugs} <- Bundled.list(),
         {:ok, entries} <- Store.adapter().list_entries() do
      {:ok, Enum.map(slugs, &{&1, sync(&1, entries_for(entries, &1))})}
    end
  end

  @doc """
  Installs bundled `slug` if, and only if, no version of it is installed.
  Returns `:ok` when there's nothing to do or the seed succeeded.
  """
  @spec seed_if_absent(String.t()) :: :ok | {:error, term()}
  def seed_if_absent(slug) do
    with {:ok, bundled} <- Bundled.list(),
         {:ok, entries} <- Store.adapter().list_entries() do
      if slug in bundled and entries_for(entries, slug) == [],
        do: slug |> sync([]) |> seed_result(),
        else: :ok
    end
  end

  defp seed_result({:apply, _plan}), do: :ok
  defp seed_result({:skip, _reason}), do: :ok
  defp seed_result({:blocked, _} = blocked), do: {:error, blocked}
  defp seed_result({:error, _} = error), do: error

  defp sync(slug, installed_entries) do
    with {:ok, source} <- Bundled.fetch(slug),
         {:ok, release} <- RuleModule.from_map(source.module) do
      installed_entries
      |> Enum.map(&to_rule_module/1)
      |> Replacement.decide(release)
      |> Replacement.log(release)
      |> apply_decision(source)
    end
  end

  defp entries_for(entries, slug), do: Enum.filter(entries, &(&1.slug == slug))

  # Replacement only reads slug, version and library_requirement, all of
  # which the store keeps as entry metadata; no need to load the content.
  defp to_rule_module(%Entry{} = entry) do
    %RuleModule{
      slug: entry.slug,
      version: entry.version,
      library_requirement: entry.library_requirement
    }
  end

  # Install before removing, so a failure part-way never leaves the slug
  # with no installed version. A concurrent seeder having installed the
  # same entry first counts as success.
  defp apply_decision({:apply, plan} = decision, source) do
    store = Store.adapter()

    with :ok <- ok_if_exists(store.put(Entry.from_source(source, false), source, false)),
         :ok <- remove_all(store, source.module["module"]["slug"], plan.remove) do
      decision
    else
      {:error, reason} -> {:error, {:apply_failed, reason}}
    end
  end

  defp apply_decision(decision, _source), do: decision

  defp ok_if_exists({:error, :already_exists}), do: :ok
  defp ok_if_exists(result), do: result

  defp remove_all(store, slug, versions) do
    Enum.reduce_while(versions, :ok, fn version, :ok ->
      case store.delete(slug, version) do
        result when result in [:ok, {:error, :not_found}] -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end
end
