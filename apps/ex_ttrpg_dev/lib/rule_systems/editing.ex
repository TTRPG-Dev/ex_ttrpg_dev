defmodule ExTTRPGDev.RuleSystems.Editing do
  @moduledoc false
  # Implementation of RuleSystems.create_system/1, slug_from_name/1,
  # clone_system/3, update_system/2 and delete_system/1; see the
  # documentation there.

  alias ExTTRPGDev.RuleSystem.{Graph, Loader, Source, Store}
  alias ExTTRPGDev.RuleSystem.Store.Entry
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.{Dependents, Installed}
  alias ExTTRPGDev.Slug

  # The [module] keys create_system/1 accepts. Deliberately not every key
  # module.toml allows: library_requirement would make the system look
  # canonical, and the structural keys (level_node, custom_metadata_keys...)
  # only mean something once there's content, which is authored afterwards.
  @creatable_keys ~w(name slug version publisher family series)
  @default_version "1.0.0"

  def create_system(fields) when is_map(fields) do
    with {:ok, module} <- new_module(fields),
         :ok <- check_slug_free(module["slug"]),
         source = %Source{module: %{"module" => module}},
         :ok <- check_new_loads(source) do
      put_new(source, module["slug"])
    end
  end

  # Keeps exactly the characters ExTTRPGDev.Slug allows (letters, marks
  # and digits in any script), less hyphens, and in the NFC form it
  # requires. Normalizing first means a decomposed "é" (e + combining
  # accent) gives the same slug as a composed one.
  def slug_from_name(name) when is_binary(name) do
    name
    |> String.normalize(:nfc)
    |> String.downcase()
    |> String.replace(~r/[\s-]+/u, "_")
    |> String.replace(~r/[^\p{L}\p{M}\p{N}_]/u, "")
    |> String.replace(~r/_+/, "_")
    |> String.trim("_")
  end

  # Values are trimmed, and nil or blank values dropped, so an optional
  # field left empty is omitted rather than stored as "".
  defp new_module(fields) do
    with :ok <- check_known_keys(fields),
         {:ok, present} <- present_values(fields),
         {:ok, name} <- fetch_name(present),
         {:ok, slug} <- new_slug(present, name) do
      {:ok,
       present
       |> Map.put("slug", slug)
       |> Map.put_new("version", @default_version)}
    end
  end

  defp check_known_keys(fields) do
    case Enum.find(Map.keys(fields), &(&1 not in @creatable_keys)) do
      nil -> :ok
      key -> {:error, {:invalid_module, {:unknown_key, key}}}
    end
  end

  defp present_values(fields) do
    Enum.reduce_while(fields, {:ok, %{}}, fn
      {_key, nil}, acc ->
        {:cont, acc}

      {key, value}, {:ok, acc} when is_binary(value) ->
        case String.trim(value) do
          "" -> {:cont, {:ok, acc}}
          trimmed -> {:cont, {:ok, Map.put(acc, key, trimmed)}}
        end

      {key, value}, _acc ->
        {:halt, {:error, {:invalid_module, {:not_a_string, key, value}}}}
    end)
  end

  defp fetch_name(%{"name" => name}), do: {:ok, name}
  defp fetch_name(_), do: {:error, {:invalid_module, {:missing_required_key, "name"}}}

  # A given slug must already be in the form a derived one takes, so every
  # created system's slug is safe as a directory name and in protocol args.
  # The length is checked here, against the limit the store enforces, so
  # an over-long name gets its own error rather than the store's generic
  # {:invalid_slug, slug}, which would suggest the characters are wrong.
  defp new_slug(%{"slug" => slug}, _name), do: check_slug(slug)
  defp new_slug(_present, name), do: check_slug(slug_from_name(name))

  defp check_slug(slug) do
    cond do
      slug == "" or slug_from_name(slug) != slug -> {:error, {:invalid_slug, slug}}
      byte_size(slug) > Slug.max_bytes() -> {:error, {:slug_too_long, slug, Slug.max_bytes()}}
      true -> {:ok, slug}
    end
  end

  defp check_new_loads(source) do
    with {:ok, data} <- Loader.load_source(source),
         {:ok, _graph} <- Graph.build(data) do
      :ok
    else
      {:error, reason} -> {:error, {:invalid_module, reason}}
    end
  end

  # The new slug is held to the form create_system/1 requires, so a
  # clone's slug can't be one no created system could have (uppercase,
  # hyphens), and an over-long one gets {:slug_too_long, ...} rather than
  # the store's generic {:invalid_slug, slug}.
  def clone_system(source_slug, new_slug, opts) do
    with {:ok, new_slug} <- check_slug(new_slug),
         {:ok, overrides} <- present_values(Map.new(Keyword.take(opts, [:name]), &stringify/1)),
         :ok <- check_slug_free(new_slug),
         {:ok, _entry, source} <- Installed.resolve(source_slug, opts[:version]) do
      put_new(as_clone(source, new_slug, overrides), new_slug)
    end
  end

  defp stringify({key, value}), do: {Atom.to_string(key), value}

  def update_system(slug, update_fun) when is_function(update_fun, 1) do
    with {:ok, entry, source} <- Installed.resolve(slug, nil),
         :ok <- check_modifiable(entry),
         {:ok, updated} <- apply_update(update_fun, source),
         :ok <- check_update(source, updated) do
      store_update(entry, updated)
    end
  end

  # Deliberately doesn't go through Installed.resolve/2: that seeds an
  # uninstalled bundled slug, and deleting must never install anything.
  def delete_system(slug) do
    store = Store.adapter()

    with {:ok, entries} <- store.list_entries(),
         {:ok, owned} <- deletable_entries(entries, slug),
         :ok <- check_no_dependents(slug, owned) do
      delete_entries(store, owned)
    end
  end

  # Every installed entry for the slug must be modifiable; a slug with no
  # entries is refused if it's bundled (it would be seeded on next load or
  # sync, so there's nothing a delete could achieve) and unknown otherwise.
  defp deletable_entries(entries, slug) do
    case Enum.filter(entries, &(&1.slug == slug)) do
      [] ->
        uninstalled_error(slug)

      owned ->
        if Enum.all?(owned, & &1.is_modifiable), do: {:ok, owned}, else: {:error, :not_modifiable}
    end
  end

  defp uninstalled_error(slug) do
    with {:ok, bundled} <- RuleSystems.fetch_bundled_systems() do
      if slug in bundled, do: {:error, :not_modifiable}, else: {:error, {:not_configured, slug}}
    end
  end

  defp check_no_dependents(slug, entries) do
    case Dependents.find_any_version(slug, Enum.map(entries, & &1.version)) do
      {:ok, []} -> :ok
      {:ok, found} -> {:error, {:has_dependents, found}}
      {:error, reason} -> {:error, {:dependents_unavailable, reason}}
    end
  end

  defp delete_entries(store, entries) do
    Enum.reduce_while(entries, :ok, fn entry, :ok ->
      case store.delete(entry.slug, entry.version) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp check_modifiable(%Entry{is_modifiable: true}), do: :ok
  defp check_modifiable(_entry), do: {:error, {:not_modifiable, :clone_required}}

  defp apply_update(update_fun, source) do
    case update_fun.(source) do
      %Source{} = updated -> {:ok, updated}
      other -> {:error, {:invalid_update, {:not_a_source, other}}}
    end
  end

  # An update may change content and the version string, but not the
  # system's identity (slug) or whether it's canonical: canonical-ness
  # comes from where content originated, and flipping it would also change
  # how a store files the entry. The result must still load, so a broken
  # edit is rejected instead of replacing a working system.
  defp check_update(old, new) do
    cond do
      module_key(new, "slug") != module_key(old, "slug") ->
        {:error, {:invalid_update, :slug_changed}}

      module_key(new, "library_requirement") != module_key(old, "library_requirement") ->
        {:error, {:invalid_update, :library_requirement_changed}}

      true ->
        check_loads(new)
    end
  end

  defp check_loads(source) do
    with {:ok, data} <- Loader.load_source(source),
         {:ok, _graph} <- Graph.build(data) do
      :ok
    else
      {:error, reason} -> {:error, {:invalid_update, reason}}
    end
  end

  defp module_key(%Source{module: %{"module" => module}}, key), do: module[key]
  defp module_key(_source, _key), do: nil

  # Overwrite the entry; if the version changed and the adapter files
  # versions separately, the old one is still listed and is removed.
  defp store_update(%Entry{} = entry, updated) do
    store = Store.adapter()
    new_entry = Entry.from_source(updated, entry.is_modifiable)

    with :ok <- store.put(new_entry, updated, true) do
      remove_stale_version(store, entry, new_entry)
    end
  end

  defp remove_stale_version(_store, %Entry{version: v}, %Entry{version: v}), do: :ok

  defp remove_stale_version(store, old, _new) do
    with {:ok, entries} <- store.list_entries() do
      if Enum.any?(entries, &(&1.slug == old.slug and &1.version == old.version)),
        do: store.delete(old.slug, old.version),
        else: :ok
    end
  end

  # A new system (created or cloned) must not collide with an installed
  # slug, nor with a bundled one that isn't installed yet: it would block
  # that bundled system forever (local content wins a slug), which is never
  # what creating or cloning is for.
  defp check_slug_free(slug) do
    with {:ok, slugs} <- RuleSystems.fetch_systems() do
      if slug in slugs, do: {:error, {:slug_taken, slug}}, else: :ok
    end
  end

  # Stores a new (created or cloned) system as modifiable, never
  # overwriting whatever the store already holds at its address.
  defp put_new(%Source{} = source, slug) do
    case Store.adapter().put(Entry.from_source(source, true), source, false) do
      :ok -> {:ok, slug}
      {:error, :already_exists} -> already_exists_error(slug)
      error -> error
    end
  end

  # check_slug_free/1 passed, yet the store has something at the slug's
  # address. Either a system was stored there since (a concurrent create),
  # or what's there isn't a system the store lists, e.g. a directory with
  # no module.toml. Listing again tells them apart. If listing fails, the
  # last successful listing (check_slug_free/1's, moments ago) had no such
  # system, so :slug_occupied is the better answer: :slug_taken would claim
  # a system exists that no listing has shown.
  defp already_exists_error(slug) do
    case Store.adapter().list_entries() do
      {:ok, entries} ->
        if Enum.any?(entries, &(&1.slug == slug)),
          do: {:error, {:slug_taken, slug}},
          else: {:error, {:slug_occupied, slug}}

      {:error, _} ->
        {:error, {:slug_occupied, slug}}
    end
  end

  # Cloning severs the link to the library's versioning: the clone isn't
  # canonical (no library_requirement), so it's never replaced by a sync.
  # Its version is kept as a record of what it was cloned from. overrides
  # holds the [module] values the caller gave (only "name"), already
  # trimmed with blanks dropped.
  defp as_clone(%Source{module: module_map} = source, new_slug, overrides) do
    module =
      module_map["module"]
      |> Map.merge(overrides)
      |> Map.put("slug", new_slug)
      |> Map.delete("library_requirement")

    %{source | module: Map.put(module_map, "module", module)}
  end
end
