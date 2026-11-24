defmodule ExTTRPGDev.Characters.Store.FileSystem do
  @moduledoc """
  The default `ExTTRPGDev.Characters.Store` adapter: each character is a
  JSON file, `{slug}.json`, under `Globals.characters_path()`.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.save_character!/2`); this module hosts the
  implementation. `character_file_path/1` is specific to this adapter.
  """

  @behaviour ExTTRPGDev.Characters.Store

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Metadata
  alias ExTTRPGDev.Globals

  @doc """
  Get the file path for a character.

  See `ExTTRPGDev.Characters.character_file_path/1` for documentation.
  """
  def character_file_path(%Character{metadata: %Metadata{slug: slug}}) do
    character_file_path(slug)
  end

  def character_file_path(character_slug) when is_bitstring(character_slug) do
    Path.join(Globals.characters_path(), "#{character_slug}.json")
  end

  @doc """
  Returns a boolean as to whether the character exists on disk.

  Accepts a `Character` as well as a slug.
  """
  @impl true
  def character_exists?(character) do
    character
    |> character_file_path()
    |> File.exists?()
  end

  @doc "Saves the given character to disk."
  @impl true
  def save_character(%Character{} = character, overwrite) do
    if character_exists?(character) and not overwrite do
      {:error, :already_exists}
    else
      with :ok <- File.mkdir_p(Globals.characters_path()),
           {:ok, json} <- Jason.encode(Character.to_json_map(character)) do
        File.write(character_file_path(character), json)
      end
    end
  end

  @doc "Delete a saved character by slug."
  @impl true
  def delete_character(character_slug) do
    case character_file_path(character_slug) |> File.rm() do
      :ok -> :ok
      {:error, :enoent} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "List saved characters."
  @impl true
  def list_characters do
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

  @doc "Load a saved character."
  @impl true
  def load_character(character_slug) do
    case character_file_path(character_slug) |> File.read() do
      {:ok, contents} ->
        Character.from_json(contents)

      {:error, :enoent} ->
        {:error, :not_found}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
