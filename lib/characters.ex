defmodule ExTTRPGDev.Characters do
  @moduledoc """
  This module handles handles character operations
  """
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Metadata
  alias ExTTRPGDev.Globals

  @doc """
  Get the file path for a character

  ## Examples

      iex> Characters.character_file_path!(%Character{metadata: %Characters.Metadata{slug: "mr_whiskers"}})
      "mr_whiskers.json"
  """
  def character_file_path!(%Character{metadata: %Metadata{slug: slug}}) do
    character_file_path!(slug)
  end

  def character_file_path!(character_slug) when is_bitstring(character_slug) do
    Path.join(Globals.characters_path(), "#{character_slug}.json")
  end

  @doc """
  Returns a boolean as to whether the character exists on disk

  ## Examples

      iex> Characters.character_exists?(%Characters.Character{name: "This Character exists"})
      true

      iex> Characters.character_exists?("this_character_exists")
      true

      iex> Characters.Character_exists?(%Characters.Character{name: "This character doesn't exist})
      false

      iex> Characters.Character_exists?("this_character_doesnt_exist")
      false
  """
  def character_exists?(character) do
    character
    |> character_file_path!
    |> File.exists?()
  end

  @doc """
  Saves the given character to disk. Error is raised if character already exists unless `overwrite` is set to true

  ## Example

      iex> Characters.save_character!(%Characters.Character{name: "doesn't exist yet"})
      :ok

      iex> Characters.save_character!(%Characters.Character{name: "exists already"})
      :error, :character already exists

      iex> Characters.save_character!(%Characters.Character{name: "exists already"}, true)
      :ok
  """
  def save_character!(
        %Character{} = character,
        overwrite \\ false
      ) do
    if character_exists?(character) and not overwrite do
      raise "Character named #{character.name} already exsts. To overwrite, pass `overwrite` as true"
    else
      File.mkdir_p!(Globals.characters_path())
      File.write!(character_file_path!(character), Poison.encode!(character))
    end
  end

  @doc """
  List saved characters

  ## Example

      iex> Characters.list_characters!()
      [%Character{}, %Character{}, ...]
  """
  def list_characters!() do
    Globals.characters_path()
    |> File.ls!()
    |> Enum.map(fn x -> String.trim_trailing(x, ".json") end)
  end

  @doc """
  Load a saved character

  ## Example

      iex> Character.load_character!("misu_park_the_cat")
      %Character{}
  """
  def load_character!(character_slug) do
    character_file_path!(character_slug)
    |> File.read!()
    |> Character.from_json!()
  end
end
