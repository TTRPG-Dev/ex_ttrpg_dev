defmodule ExTTRPGDev.RuleSystems.Characters do
  @moduledoc """
  This module handles the definition of rule system characters, and what they do
  """
  alias ExTTRPGDev.Globals

  defmodule CharacterMetadata do
    @moduledoc """
    Metadata for an individual charater
    """
    defstruct [:slug, :rule_system]
  end

  defmodule Character do
    @moduledoc """
    Definition of an individual character
    """
    defstruct [:name, :ability_scores, :metadata]
  end

  @doc """
  Get the file path for a character

  ## Examples

      iex> Characters.character_file_path!(%Character{metadata: %CharacterMetadata{slug: "mr_whiskers"}})
      "mr_whiskers.json"
  """
  def character_file_path!(%Character{metadata: %CharacterMetadata{slug: slug}}) do
    Path.join(Globals.characters_path(), "#{slug}.json")
  end

  @doc """
  Returns a boolean as to whether the character exists on disk

  ## Examples

      iex> Characters.character_exists?(%Characters.Character{name: "This Character exists"})
      true

      iex> Characters.Character_exists?(%Characters.Character{name: "This character doesn't exist})
      false
  """
  def character_exists?(%Character{} = character) do
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
end
