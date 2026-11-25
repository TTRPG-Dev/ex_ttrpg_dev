defmodule ExTTRPGDev.Characters.Store.FileSystem do
  @moduledoc """
  The default `ExTTRPGDev.Characters.Store` adapter: each character is a
  JSON file, `{slug}.json`, under `Globals.characters_path()`.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.save_character!/2`); this module hosts the
  implementation. `character_file_path/1` is specific to this adapter.

  A slug becomes a file name here, so it must be a valid slug: letters and
  digits in any script plus `_` and `-`, in Unicode NFC form, at most 200
  bytes. Anything else, including slugs that could reach outside the
  characters directory such as `"../x"`, is rejected with
  `{:error, {:invalid_slug, slug}}` without touching the filesystem.
  """

  @behaviour ExTTRPGDev.Characters.Store

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Metadata
  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.Slug

  @doc """
  Get the file path for a character.

  Raises `ArgumentError` if the slug isn't valid, rather than returning a
  path that could point outside the characters directory.

  See `ExTTRPGDev.Characters.character_file_path/1` for documentation.
  """
  def character_file_path(%Character{metadata: %Metadata{slug: slug}}) do
    character_file_path(slug)
  end

  def character_file_path(character_slug) when is_bitstring(character_slug) do
    if Slug.valid?(character_slug) do
      path_for(character_slug)
    else
      raise ArgumentError, "invalid character slug: #{inspect(character_slug)}"
    end
  end

  defp path_for(slug), do: Path.join(Globals.characters_path(), "#{slug}.json")

  defp check_slug(slug) do
    if Slug.valid?(slug), do: :ok, else: {:error, {:invalid_slug, slug}}
  end

  @doc """
  Returns a boolean as to whether the character exists on disk.

  Accepts a `Character` as well as a slug.
  """
  @impl true
  def character_exists?(%Character{metadata: %Metadata{slug: slug}}), do: character_exists?(slug)

  def character_exists?(slug) do
    Slug.valid?(slug) and File.exists?(path_for(slug))
  end

  @doc """
  Saves the given character to disk.

  The JSON is written in full to a temporary file in the characters
  directory, then moved into place, so neither a reader nor a crash ever
  sees a partially written character. Without `overwrite`, the slug is
  claimed with a hard link, which fails if the file already exists, so of
  two concurrent saves of the same new slug exactly one succeeds.
  """
  @impl true
  def save_character(%Character{metadata: %Metadata{slug: slug}} = character, overwrite) do
    dir = Globals.characters_path()

    with :ok <- check_slug(slug),
         :ok <- File.mkdir_p(dir),
         {:ok, json} <- Jason.encode(Character.to_json_map(character)),
         {:ok, tmp} <- write_tmp(dir, json) do
      result = install(tmp, path_for(slug), overwrite)
      # Gone already if it was renamed into place; a leftover otherwise.
      File.rm(tmp)
      result
    end
  end

  # The leading "." keeps temp files out of list_characters/0 (not a valid
  # slug). The OS pid makes the name unique across concurrent engine
  # processes, not just within this VM; :exclusive guards the rest.
  defp write_tmp(dir, json) do
    tmp = Path.join(dir, ".tmp-#{System.pid()}-#{System.unique_integer([:positive])}.json")

    case File.write(tmp, json, [:exclusive, :sync]) do
      :ok ->
        {:ok, tmp}

      {:error, reason} ->
        File.rm(tmp)
        {:error, reason}
    end
  end

  defp install(tmp, target, true = _overwrite) do
    case File.rename(tmp, target) do
      :ok -> :ok
      # Platforms whose rename won't replace an existing file.
      {:error, reason} when reason in [:eexist, :eacces] -> replace_aside(tmp, target)
      error -> error
    end
  end

  defp install(tmp, target, false = _overwrite) do
    case File.ln(tmp, target) do
      :ok -> :ok
      {:error, :eexist} -> {:error, :already_exists}
      # Filesystems without hard links (FAT, exFAT).
      {:error, reason} when reason in [:enotsup, :eperm] -> claim_without_link(tmp, target)
      error -> error
    end
  end

  # Moves the old file aside, renames the new one in, then drops the old
  # one, restoring it if the rename fails. Not atomic (there is a moment
  # with no file), but never leaves a partial one.
  defp replace_aside(tmp, target) do
    aside = "#{target}.old-#{System.pid()}-#{System.unique_integer([:positive])}"

    with :ok <- File.rename(target, aside) do
      case File.rename(tmp, target) do
        :ok ->
          File.rm(aside)
          :ok

        error ->
          File.rename(aside, target)
          error
      end
    end
  end

  # Without hard links there is no atomic create-if-absent for a fully
  # written file, so check, then rename: contents stay atomic, but two
  # concurrent saves of one new slug can race.
  defp claim_without_link(tmp, target) do
    if File.exists?(target), do: {:error, :already_exists}, else: File.rename(tmp, target)
  end

  @doc "Delete a saved character by slug."
  @impl true
  def delete_character(character_slug) do
    with :ok <- check_slug(character_slug) do
      case File.rm(path_for(character_slug)) do
        :ok -> :ok
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  @doc """
  List saved characters.

  Only `{slug}.json` files with a valid slug are listed; anything else in
  the directory (stray files, temporary files) is ignored, since it
  couldn't be loaded by slug anyway.
  """
  @impl true
  def list_characters do
    path = Globals.characters_path()

    if File.exists?(path) do
      case File.ls(path) do
        {:ok, entries} -> {:ok, Enum.flat_map(entries, &listed_slug/1)}
        {:error, reason} -> {:error, reason}
      end
    else
      {:ok, []}
    end
  end

  # HFS+ reports names decomposed (NFD) even when they were written
  # composed; normalising before validating keeps those characters listed,
  # and HFS+ resolves the composed name back to the same file.
  defp listed_slug(entry) do
    with true <- String.ends_with?(entry, ".json"),
         true <- String.valid?(entry),
         slug = entry |> String.trim_trailing(".json") |> String.normalize(:nfc),
         true <- Slug.valid?(slug) do
      [slug]
    else
      _ -> []
    end
  end

  @doc "Load a saved character."
  @impl true
  def load_character(character_slug) do
    with :ok <- check_slug(character_slug) do
      case File.read(path_for(character_slug)) do
        {:ok, contents} -> Character.from_json(contents)
        {:error, :enoent} -> {:error, :not_found}
        {:error, reason} -> {:error, reason}
      end
    end
  end
end
