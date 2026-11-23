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

  ## Atomicity

  `put/3` writes into a temporary directory under the root, then renames it
  into place. A rename onto an existing directory fails, so of two
  concurrent non-overwriting puts of the same entry exactly one wins and
  the other gets `{:error, :already_exists}`, and no reader ever sees a
  half-written entry.
  """

  @behaviour ExTTRPGDev.RuleSystem.Store

  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.RuleSystem.Source
  alias ExTTRPGDev.RuleSystem.Store.Entry

  @module_file "module.toml"
  @meta_file ".store.toml"
  @slug_pattern ~r/\A[A-Za-z0-9_\-]+\z/
  @version_pattern ~r/\A[A-Za-z0-9.+\-]+\z/

  @impl true
  def list_entries do
    root = Globals.local_system_configs_path()

    case File.ls(root) do
      {:ok, names} ->
        {:ok, names |> Enum.sort() |> Enum.flat_map(&slug_entries(root, &1))}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp slug_entries(root, slug) do
    dir = Path.join(root, slug)

    cond do
      not valid_slug?(slug) or not File.dir?(dir) -> []
      system_dir?(dir) -> [read_entry(slug, dir)]
      true -> versioned_entries(slug, dir)
    end
  end

  defp versioned_entries(slug, dir) do
    case File.ls(dir) do
      {:ok, names} ->
        for name <- Enum.sort(names),
            valid_version?(name),
            version_dir = Path.join(dir, name),
            system_dir?(version_dir),
            do: read_entry(slug, version_dir)

      {:error, _} ->
        []
    end
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
    if valid_slug?(slug), do: :ok, else: {:error, {:invalid_slug, slug}}
  end

  # Only nested entries use their version as a path segment.
  defp check_version(%Entry{version: version} = entry) do
    if nested?(entry) and not valid_version?(version),
      do: {:error, {:invalid_version, version}},
      else: :ok
  end

  defp valid_slug?(slug), do: is_binary(slug) and Regex.match?(@slug_pattern, slug)

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
         :ok <- File.write(Path.join(tmp, @meta_file), meta_toml(entry)) do
      {:ok, tmp}
    else
      error ->
        File.rm_rf(tmp)
        error
    end
  end

  defp meta_toml(%Entry{is_modifiable: is_modifiable}) do
    "is_modifiable = #{is_modifiable}\n"
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
