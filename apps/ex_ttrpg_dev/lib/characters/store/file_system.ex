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

  @doc "Saves the given character to disk."
  @impl true
  def save_character(%Character{metadata: %Metadata{slug: slug}} = character, overwrite) do
    with :ok <- check_slug(slug),
         :ok <- check_absent(slug, overwrite),
         :ok <- File.mkdir_p(Globals.characters_path()),
         {:ok, json} <- Jason.encode(Character.to_json_map(character)) do
      File.write(path_for(slug), json)
    end
  end

  defp check_absent(_slug, true), do: :ok

  defp check_absent(slug, false) do
    if character_exists?(slug), do: {:error, :already_exists}, else: :ok
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
