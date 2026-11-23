defmodule ExTTRPGDev.RuleSystems.Editing do
  @moduledoc false
  # Implementation of RuleSystems.clone_system/3 and friends; see the
  # documentation there.

  alias ExTTRPGDev.RuleSystem.{Source, Store}
  alias ExTTRPGDev.RuleSystem.Store.Entry
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.Installed

  def clone_system(source_slug, new_slug, opts) do
    with :ok <- check_slug_free(new_slug),
         {:ok, _entry, source} <- Installed.resolve(source_slug, opts[:version]) do
      clone = as_clone(source, new_slug)

      case Store.adapter().put(Entry.from_source(clone, true), clone, false) do
        :ok -> {:ok, new_slug}
        {:error, :already_exists} -> {:error, {:slug_taken, new_slug}}
        error -> error
      end
    end
  end

  # A clone must not collide with an installed slug, nor with a bundled one
  # that isn't installed yet: it would block that bundled system forever
  # (local content wins a slug), which is never what cloning is for.
  defp check_slug_free(slug) do
    with {:ok, slugs} <- RuleSystems.fetch_systems() do
      if slug in slugs, do: {:error, {:slug_taken, slug}}, else: :ok
    end
  end

  # Cloning severs the link to the library's versioning: the clone isn't
  # canonical (no library_requirement), so it's never replaced by a sync.
  # Its version is kept as a record of what it was cloned from.
  defp as_clone(%Source{module: module_map} = source, new_slug) do
    module =
      module_map["module"]
      |> Map.put("slug", new_slug)
      |> Map.delete("library_requirement")

    %{source | module: Map.put(module_map, "module", module)}
  end
end
