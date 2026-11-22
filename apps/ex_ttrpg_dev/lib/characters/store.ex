defmodule ExTTRPGDev.Characters.Store do
  @moduledoc """
  Disk persistence for characters: file paths, existence checks, saving,
  loading, listing, and deletion under `Globals.characters_path()`.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.save_character!/2`); this module hosts the
  implementation.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Metadata
  alias ExTTRPGDev.Globals

  @doc """
  Get the file path for a character.

  See `ExTTRPGDev.Characters.character_file_path!/1` for documentation.
  """
  def character_file_path!(%Character{metadata: %Metadata{slug: slug}}) do
    character_file_path!(slug)
  end

  def character_file_path!(character_slug) when is_bitstring(character_slug) do
    Path.join(Globals.characters_path(), "#{character_slug}.json")
  end

  @doc """
  Returns a boolean as to whether the character exists on disk.

  See `ExTTRPGDev.Characters.character_exists?/1` for documentation.
  """
  def character_exists?(character) do
    character
    |> character_file_path!
    |> File.exists?()
  end

  @doc """
  Saves the given character to disk.

  See `ExTTRPGDev.Characters.save_character/2` for documentation.
  """
  def save_character(%Character{} = character, overwrite \\ false) do
    if character_exists?(character) and not overwrite do
      {:error, :already_exists}
    else
      File.mkdir_p!(Globals.characters_path())

      File.write(
        character_file_path!(character),
        Poison.encode!(Character.to_json_map(character))
      )
    end
  end

  @doc """
  Saves the given character to disk, raising on failure.

  See `ExTTRPGDev.Characters.save_character!/2` for documentation.
  """
  def save_character!(%Character{} = character, overwrite \\ false) do
    case save_character(character, overwrite) do
      :ok ->
        :ok

      {:error, :already_exists} ->
        raise "Character named #{character.name} already exsts. To overwrite, pass `overwrite` as true"

      {:error, reason} ->
        raise "Failed to save character #{character.name}: #{inspect(reason)}"
    end
  end

  @doc """
  Delete a saved character by slug.

  See `ExTTRPGDev.Characters.delete_character/1` for documentation.
  """
  def delete_character(character_slug) do
    case character_file_path!(character_slug) |> File.rm() do
      :ok -> :ok
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  List saved characters.

  See `ExTTRPGDev.Characters.list_characters/0` for documentation.
  """
  def list_characters() do
    path = Globals.characters_path()

    if File.exists?(path) do
      case File.ls(path) do
        {:ok, entries} ->
          {:ok, Enum.map(entries, fn x -> String.trim_trailing(x, ".json") end)}

        {:error, reason} ->
          {:error, reason}
      end
    else
      {:ok, []}
    end
  end

  @doc """
  List saved characters, raising on failure.

  See `ExTTRPGDev.Characters.list_characters!/0` for documentation.
  """
  def list_characters!() do
    case list_characters() do
      {:ok, slugs} -> slugs
      {:error, reason} -> raise "Failed to list characters: #{inspect(reason)}"
    end
  end

  @doc """
  Load a saved character.

  See `ExTTRPGDev.Characters.load_character/1` for documentation.
  """
  def load_character(character_slug) do
    case character_file_path!(character_slug) |> File.read() do
      {:ok, contents} ->
        {:ok, Character.from_json!(contents)}

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Load a saved character, raising on failure.

  See `ExTTRPGDev.Characters.load_character!/1` for documentation.
  """
  def load_character!(character_slug) do
    case load_character(character_slug) do
      {:ok, character} -> character
      {:error, reason} -> raise "Failed to load character #{character_slug}: #{inspect(reason)}"
    end
  end
end
