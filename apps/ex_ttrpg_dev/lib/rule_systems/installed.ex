defmodule ExTTRPGDev.RuleSystems.Installed do
  @moduledoc false
  # Resolves a slug (and optional version) to an installed store entry and
  # its content. Shared by loading, cloning and updating, so that all three
  # agree on which entry a slug refers to.

  alias ExTTRPGDev.RuleSystem.{Source, Store, Versioning}
  alias ExTTRPGDev.RuleSystem.Store.Entry
  alias ExTTRPGDev.RuleSystems.Sync

  @doc false
  # Seeds a bundled slug with nothing installed first; never replaces.
  @spec resolve(String.t(), String.t() | nil) ::
          {:ok, Entry.t(), Source.t()} | {:error, term()}
  def resolve(slug, version) do
    store = Store.adapter()

    with :ok <- Sync.seed_if_absent(slug),
         {:ok, entries} <- store.list_entries(),
         {:ok, entry} <- select_entry(entries, slug, version),
         {:ok, source} <- store.fetch(entry.slug, entry.version) do
      {:ok, entry, source}
    end
  end

  # Picks the installed entry for a slug. A non-canonical entry
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
end
