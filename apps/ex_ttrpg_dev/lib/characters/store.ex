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

  See `ExTTRPGDev.Characters.save_character!/2` for documentation.
  """
  def save_character!(%Character{} = character, overwrite \\ false) do
    if character_exists?(character) and not overwrite do
      raise "Character named #{character.name} already exsts. To overwrite, pass `overwrite` as true"
    else
      File.mkdir_p!(Globals.characters_path())

      File.write!(
        character_file_path!(character),
        Poison.encode!(Character.to_json_map(character))
      )
    end
  end

  @doc """
  Delete a saved character by slug.

  See `ExTTRPGDev.Characters.delete_character/1` for documentation.
  """
  def delete_character(character_slug) do
    path = character_file_path!(character_slug)

    if File.exists?(path) do
      File.rm!(path)
      :ok
    else
      {:error, :not_found}
    end
  end

  @doc """
  List saved characters.

  See `ExTTRPGDev.Characters.list_characters!/0` for documentation.
  """
  def list_characters!() do
    if File.exists?(Globals.characters_path()) do
      File.ls!(Globals.characters_path())
      |> Enum.map(fn x -> String.trim_trailing(x, ".json") end)
    else
      []
    end
  end

  @doc """
  Load a saved character.

  See `ExTTRPGDev.Characters.load_character!/1` for documentation.
  """
  def load_character!(character_slug) do
    character_file_path!(character_slug)
    |> File.read!()
    |> Character.from_json!()
  end
end
