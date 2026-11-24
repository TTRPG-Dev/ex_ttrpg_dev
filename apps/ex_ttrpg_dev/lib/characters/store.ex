defmodule ExTTRPGDev.Characters.Store do
  @moduledoc """
  Where saved characters live: a behaviour for storage adapters, plus the
  adapter-agnostic persistence functions built on it.

  Adapters implement only the core operations (the callbacks below). The
  functions in this module dispatch to the adapter in use and add what
  doesn't depend on where characters are stored: raising variants, and
  `characters_depending_on/2`, which is derived from listing and loading.

  Callers should use the delegating functions on `ExTTRPGDev.Characters`
  (e.g. `ExTTRPGDev.Characters.save_character!/2`). The default adapter is
  `ExTTRPGDev.Characters.Store.FileSystem`.
  """

  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Metadata
  alias ExTTRPGDev.RuleSystem.Versioning

  @doc "Whether a character with `slug` is saved."
  @callback character_exists?(slug :: String.t()) :: boolean()

  @doc """
  Saves `character`, keyed by its `metadata.slug`. With `overwrite` false,
  fails with `{:error, :already_exists}` if that slug is saved; with
  `overwrite` true, replaces it.
  """
  @callback save_character(character :: Character.t(), overwrite :: boolean()) ::
              :ok | {:error, :already_exists} | {:error, term()}

  @doc "Deletes the character saved under `slug`."
  @callback delete_character(slug :: String.t()) ::
              :ok | {:error, :not_found} | {:error, term()}

  @doc "Lists the slugs of all saved characters."
  @callback list_characters() :: {:ok, [String.t()]} | {:error, term()}

  @doc """
  Loads the character saved under `slug`. Saved data that can't be read
  back as a character should be reported as
  `{:error, {:invalid_character_data, message}}`, as
  `ExTTRPGDev.Characters.Character.from_json/1` does.
  """
  @callback load_character(slug :: String.t()) ::
              {:ok, Character.t()} | {:error, :not_found} | {:error, term()}

  @doc """
  The store adapter in use: currently always
  `ExTTRPGDev.Characters.Store.FileSystem`. Everything that reaches the
  store goes through this function, so making it configurable is local
  to it.
  """
  @spec adapter() :: module()
  def adapter, do: ExTTRPGDev.Characters.Store.FileSystem

  @doc """
  Returns a boolean as to whether the character is saved.

  See `ExTTRPGDev.Characters.character_exists?/1` for documentation.
  """
  @spec character_exists?(Character.t() | String.t()) :: boolean()
  def character_exists?(%Character{metadata: %Metadata{slug: slug}}), do: character_exists?(slug)
  def character_exists?(slug) when is_bitstring(slug), do: adapter().character_exists?(slug)

  @doc """
  Saves the given character.

  See `ExTTRPGDev.Characters.save_character/2` for documentation.
  """
  def save_character(%Character{} = character, overwrite \\ false) do
    adapter().save_character(character, overwrite)
  end

  @doc """
  Saves the given character, raising on failure.

  See `ExTTRPGDev.Characters.save_character!/2` for documentation.
  """
  def save_character!(%Character{} = character, overwrite \\ false) do
    case save_character(character, overwrite) do
      :ok ->
        :ok

      {:error, :already_exists} ->
        raise "Character named #{character.name} already exists. To overwrite, pass `overwrite` as true"

      {:error, reason} ->
        raise "Failed to save character #{character.name}: #{inspect(reason)}"
    end
  end

  @doc """
  Delete a saved character by slug.

  See `ExTTRPGDev.Characters.delete_character/1` for documentation.
  """
  def delete_character(character_slug), do: adapter().delete_character(character_slug)

  @doc """
  List saved characters.

  See `ExTTRPGDev.Characters.list_characters/0` for documentation.
  """
  def list_characters, do: adapter().list_characters()

  @doc """
  List saved characters, raising on failure.

  See `ExTTRPGDev.Characters.list_characters!/0` for documentation.
  """
  def list_characters! do
    case list_characters() do
      {:ok, slugs} -> slugs
      {:error, reason} -> raise "Failed to list characters: #{inspect(reason)}"
    end
  end

  @doc """
  Load a saved character.

  See `ExTTRPGDev.Characters.load_character/1` for documentation.
  """
  def load_character(character_slug), do: adapter().load_character(character_slug)

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

  @doc """
  List the slugs of saved characters that depend on version `version` of
  rule system `rule_system`.

  See `ExTTRPGDev.Characters.characters_depending_on/2` for documentation.
  """
  def characters_depending_on(rule_system, version)
      when is_bitstring(rule_system) and is_bitstring(version) do
    with {:ok, slugs} <- list_characters() do
      slugs
      |> Enum.map(&{&1, load_character(&1)})
      |> collect_dependents(rule_system, version)
    end
  end

  defp collect_dependents(loaded, rule_system, version) do
    {unreadable, characters} =
      Enum.split_with(loaded, fn {_slug, result} -> match?({:error, _}, result) end)

    if unreadable == [] do
      dependents =
        for {slug, {:ok, character}} <- characters,
            depends_on?(character, rule_system, version),
            do: slug

      {:ok, dependents}
    else
      {:error,
       {:unreadable_characters, Enum.map(unreadable, fn {slug, {:error, r}} -> {slug, r} end)}}
    end
  end

  defp depends_on?(%Character{metadata: %Metadata{rule_system: system} = meta}, system, version) do
    is_nil(meta.rule_system_version) or
      Versioning.same_release_line?(meta.rule_system_version, version)
  end

  defp depends_on?(_character, _rule_system, _version), do: false
end
