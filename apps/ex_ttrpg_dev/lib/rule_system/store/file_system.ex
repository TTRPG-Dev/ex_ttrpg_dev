defmodule ExTTRPGDev.RuleSystem.Store.FileSystem do
  @moduledoc """
  The default `ExTTRPGDev.RuleSystem.Store`: directories of TOML files under
  `ExTTRPGDev.Globals.local_system_configs_path/0`.

  ## Layout

      local_system_configs/
        my_homebrew/              # non-canonical: one version, stored flat
          module.toml
          concepts/...
        dnd_5e_srd/               # canonical: one directory per version
          1.0.0/
            .store.toml
            module.toml
            concepts/...
          2.0.0/
            ...

  Canonical content (a `library_requirement` is declared) is the only
  content that can have several versions installed, so only it is nested
  by version. Everything else is stored flat, which is also the layout
  hand-authored local systems already use, so they need no migration.

  `.store.toml` holds metadata that isn't part of the content itself:
  currently `is_modifiable`. A directory without one is modifiable, which
  keeps hand-authored systems editable.

  ## Slugs

  Each slug directory's name must be a valid slug: letters and digits in
  any script plus `_` and `-`, in Unicode NFC form, at most 200 bytes.
  Other directories under the root are ignored by `list_entries/0`.

  Up to and including 0.15.0 there was no length limit, so a system
  installed under a slug longer than 200 bytes is no longer listed (and
  looks uninstalled). It's left untouched on disk; renaming its directory
  (and the `slug` in its `module.toml`) to a shorter slug makes it
  reachable again.

  ## Atomicity

  `put/3` writes into a temporary directory under the root, then renames it
  into place. A rename onto an existing directory fails, so of two
  concurrent non-overwriting puts of the same entry exactly one wins and
  the other gets `{:error, :already_exists}`, and no reader ever sees a
  half-written entry.
  """

  @behaviour ExTTRPGDev.RuleSystem.Store

  require Logger

  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.Slug
  alias ExTTRPGDev.RuleSystem.Source
  alias ExTTRPGDev.RuleSystem.Store.Entry

  @module_file "module.toml"
  @meta_file ".store.toml"
  @version_pattern ~r/\A[A-Za-z0-9.+\-]+\z/

  @impl true
  def list_entries do
    root = Globals.local_system_configs_path()

    case File.ls(root) do
      {:ok, names} ->
        names |> Enum.map(&composed/1) |> Enum.uniq() |> Enum.sort() |> collect_entries(root)

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # HFS+ reports names decomposed (NFD) even when they were written
  # composed, which Slug.valid?/1 rejects; normalising keeps those systems
  # listed, and HFS+ resolves the composed name back to the same directory.
  # Filesystems that compare names byte for byte (e.g. ext4) don't, so a
  # directory actually named in NFD fails slug_entries/2's File.dir?/1
  # check and is skipped rather than listed under a slug that can't be
  # fetched. A composed twin normalises to the same name, hence the uniq.
  defp composed(name) do
    if String.valid?(name), do: String.normalize(name, :nfc), else: name
  end

  # Fails as a whole if any slug directory can't be read, rather than
  # leaving that slug out: an unreadable slug would otherwise look
  # uninstalled, and callers (sync, collision checks) act on absence.
  defp collect_entries(slugs, root) do
    slugs
    |> Enum.reduce_while({:ok, []}, fn slug, {:ok, acc} ->
      case slug_entries(root, slug) do
        {:ok, entries} -> {:cont, {:ok, [entries | acc]}}
        {:error, reason} -> {:halt, {:error, {slug, reason}}}
      end
    end)
    |> case do
      {:ok, nested} -> {:ok, nested |> Enum.reverse() |> List.flatten()}
      error -> error
    end
  end

  # Each directory under the root is one slug, in one of two layouts:
  #
  # - flat: `{slug}/module.toml` exists, so the directory *is* the system
  #   (non-canonical content). Its subdirectories (e.g. `concepts/`) are
  #   content, never versions, so they aren't scanned.
  # - nested: no `{slug}/module.toml`, so each subdirectory is one installed
  #   version of canonical content: `{slug}/{version}/module.toml`.
  defp slug_entries(root, slug) do
    dir = Path.join(root, slug)

    cond do
      not Slug.valid?(slug) or not File.dir?(dir) -> {:ok, []}
      system_dir?(dir) -> {:ok, [read_entry(slug, dir)]}
      true -> versioned_entries(slug, dir)
    end
  end

  # Only called for the nested layout (see slug_entries/2), so every child
  # of `slug_dir` is named after a version. A child is an entry if its name
  # is a usable version (which also skips dot-directories such as
  # interrupted `.tmp-*` writes), it contains a module.toml, and that
  # module.toml declares the same version as the directory name.
  defp versioned_entries(slug, slug_dir) do
    case File.ls(slug_dir) do
      {:ok, versions} ->
        entries =
          for version <- Enum.sort(versions),
              valid_version?(version),
              # A binding, not a filter: always matches. Gives the path a
              # name for the check and the read below.
              version_dir = Path.join(slug_dir, version),
              system_dir?(version_dir),
              entry = read_entry(slug, version_dir),
              version_matches_dir?(entry, version, version_dir),
              do: entry

        {:ok, entries}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # The directory name is the entry's address (fetch/2 and delete/2 find a
  # version by it), while the entry's version comes from module.toml. put/3
  # always writes them in agreement; if a hand edit makes them disagree,
  # listing the entry would advertise a version fetch/2 can't find, so it's
  # skipped and a warning names the directory to fix.
  defp version_matches_dir?(%Entry{version: version}, version, _dir), do: true

  defp version_matches_dir?(%Entry{version: declared}, dir_version, dir) do
    Logger.warning(
      "Ignoring rule system at #{dir}: its module.toml declares version " <>
        "#{inspect(declared)}, but it is installed as #{dir_version}"
    )

    false
  end

  # A module.toml that can't be decoded still yields an entry, with no
  # version: the slug is visibly taken (so canonical content won't be
  # installed over it), and loading it reports the parse error.
  defp read_entry(slug, dir) do
    module = with {:ok, map} <- read_toml(Path.join(dir, @module_file)), do: map["module"]
    module = if is_map(module), do: module, else: %{}

    %Entry{
      slug: slug,
      version: module["version"],
      library_requirement: module["library_requirement"],
      is_modifiable: read_is_modifiable(dir)
    }
  end

  defp read_is_modifiable(dir) do
    case read_toml(Path.join(dir, @meta_file)) do
      {:ok, %{"is_modifiable" => false}} -> false
      _ -> true
    end
  end

  @impl true
  def fetch(slug, version) do
    with {:ok, dir} <- locate(slug, version) do
      Source.read(dir)
    end
  end

  @impl true
  def put(%Entry{} = entry, %Source{} = source, overwrite) do
    with :ok <- validate_address(entry),
         root = Globals.local_system_configs_path(),
         target = entry_dir(root, entry),
         :ok <- File.mkdir_p(Path.dirname(target)),
         {:ok, tmp} <- write_tmp(root, entry, source) do
      install(root, tmp, target, overwrite)
    end
  end

  @impl true
  def delete(slug, version) do
    with {:ok, dir} <- locate(slug, version),
         {:ok, _} <- File.rm_rf(dir) do
      remove_if_empty(Path.join(Globals.local_system_configs_path(), slug))
    end
  end

  defp locate(slug, version) do
    with :ok <- check_slug(slug) do
      flat = Path.join(Globals.local_system_configs_path(), slug)

      cond do
        nested_system?(flat, version) -> {:ok, Path.join(flat, version)}
        flat_system?(slug, flat, version) -> {:ok, flat}
        true -> {:error, :not_found}
      end
    end
  end

  defp nested_system?(flat, version) do
    valid_version?(version) and system_dir?(Path.join(flat, version))
  end

  defp flat_system?(slug, flat, version) do
    system_dir?(flat) and read_entry(slug, flat).version == version
  end

  defp validate_address(%Entry{slug: slug} = entry) do
    with :ok <- check_slug(slug) do
      check_version(entry)
    end
  end

  defp check_slug(slug) do
    if Slug.valid?(slug), do: :ok, else: {:error, {:invalid_slug, slug}}
  end

  # Only nested entries use their version as a path segment.
  defp check_version(%Entry{version: version} = entry) do
    if nested?(entry) and not valid_version?(version),
      do: {:error, {:invalid_version, version}},
      else: :ok
  end

  defp valid_version?(version) do
    is_binary(version) and Regex.match?(@version_pattern, version) and
      not String.starts_with?(version, ".")
  end

  defp nested?(%Entry{library_requirement: requirement}), do: not is_nil(requirement)

  defp entry_dir(root, %Entry{slug: slug, version: version} = entry) do
    if nested?(entry), do: Path.join([root, slug, version]), else: Path.join(root, slug)
  end

  defp write_tmp(root, entry, source) do
    tmp = Path.join(root, ".tmp-#{System.unique_integer([:positive])}")

    with :ok <- Source.write(source, tmp),
         {:ok, meta} <- encode_meta(entry),
         :ok <- File.write(Path.join(tmp, @meta_file), meta) do
      {:ok, tmp}
    else
      error ->
        File.rm_rf(tmp)
        error
    end
  end

  # The .store.toml format: entry metadata that isn't part of the content.
  # Encoded with the same library read_is_modifiable/1 decodes with, so
  # fields added later (e.g. strings needing escaping) stay round-trippable.
  defp encode_meta(%Entry{is_modifiable: is_modifiable}) do
    TomlElixir.encode(%{"is_modifiable" => is_modifiable})
  end

  defp install(root, tmp, target, overwrite) do
    exists = File.exists?(target)

    cond do
      exists and not overwrite ->
        File.rm_rf(tmp)
        {:error, :already_exists}

      exists ->
        replace(root, tmp, target)

      true ->
        rename_into_place(tmp, target)
    end
  end

  defp rename_into_place(tmp, target) do
    case File.rename(tmp, target) do
      :ok ->
        :ok

      {:error, reason} when reason in [:eexist, :enotempty] ->
        File.rm_rf(tmp)
        {:error, :already_exists}

      {:error, reason} ->
        File.rm_rf(tmp)
        {:error, reason}
    end
  end

  # Move the old entry aside (to a dot-directory under the root, which is
  # never listed) so the new one can be renamed in. The old copy is deleted
  # only once the new one is in place, and restored if that fails.
  defp replace(root, tmp, target) do
    old = Path.join(root, ".old-#{System.unique_integer([:positive])}")

    with :ok <- File.rename(target, old) do
      case rename_into_place(tmp, target) do
        :ok ->
          File.rm_rf(old)
          :ok

        error ->
          File.rename(old, target)
          error
      end
    end
  end

  defp remove_if_empty(dir) do
    case File.ls(dir) do
      {:ok, []} -> File.rmdir(dir)
      _ -> :ok
    end
  end

  defp system_dir?(dir), do: File.regular?(Path.join(dir, @module_file))

  defp read_toml(path) do
    with {:ok, contents} <- File.read(path) do
      TomlElixir.decode(contents)
    end
  end
end
