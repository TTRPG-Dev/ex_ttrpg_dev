defmodule ExTTRPGDev.Characters do
  @moduledoc """
  This module handles handles character operations
  """
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.Characters.Metadata
  alias ExTTRPGDev.Dice
  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.RuleSystem.Evaluator
  alias ExTTRPGDev.RuleSystems.LoadedSystem

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

      File.write!(
        character_file_path!(character),
        Poison.encode!(Character.to_json_map(character))
      )
    end
  end

  @doc """
  List saved characters

  ## Example

      iex> Characters.list_characters!()
      [%Character{}, %Character{}, ...]
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

  @doc """
  Generates a random decision list for a system by randomly selecting a value for each required
  character choice and recursing into any sub-choices declared by the selected concept.

  Root concepts (those not referenced as sub-options of any other concept of the same type)
  are the valid top-level picks. Sub-choices follow whatever options the selected concept declares.
  """
  def random_decisions(%LoadedSystem{} = system) do
    system.module.character_choices
    |> Enum.flat_map(fn %{concept_type: type_id} ->
      root_ids = root_concept_ids(system.concept_metadata, type_id)
      selected_id = Enum.random(root_ids)
      decision = %{scope: nil, choice: type_id, selection: selected_id}
      [decision | random_sub_decisions(system.concept_metadata, {type_id, selected_id})]
    end)
  end

  @doc """
  Returns the set of active `{type_id, concept_id}` pairs derived from a character's decisions.

  Walks the decisions tree starting from root decisions (scope: nil), adding each selected
  concept and recursing into any sub-choices that concept declares.
  """
  def active_concepts(decisions, concept_metadata) do
    decisions
    |> Enum.filter(fn d -> d.scope == nil end)
    |> Enum.reduce(MapSet.new(), fn %{choice: type, selection: id}, acc ->
      collect_active_concepts({type, id}, decisions, concept_metadata, acc)
    end)
  end

  @doc """
  Returns the combined effects list for a character against a system.

  Filters system-defined effects to only those whose source concept is active
  (per the character's decisions), then appends the character's own effects.
  """
  def active_effects(%LoadedSystem{} = system, %Character{} = character) do
    active = active_concepts(character.decisions, system.concept_metadata)

    system.effects
    |> Enum.filter(fn
      %{source: {type, id}} -> MapSet.member?(active, {type, id})
      %{source: {type, id, _}} -> MapSet.member?(active, {type, id})
      _ -> false
    end)
    |> Kernel.++(character.effects)
  end

  @doc """
  Rolls for a concept using the roll definition attached to its type in the system config.

  Looks up a roll definition (from the system's `roll` concept type) whose `target_type`
  matches `type_id`, then rolls the specified dice and adds the resolved value of
  `bonus_field` for the given concept.

  Returns a map with `:type_id`, `:concept_id`, `:dice` (spec string), `:rolls` (list of
  individual die results), `:bonus`, and `:total`.

  Raises if no roll is defined for the given concept type, or if the bonus field cannot
  be resolved for the concept.
  """
  def concept_roll!(%LoadedSystem{} = system, %Character{} = character, type_id, concept_id) do
    roll_def =
      system.concept_metadata
      |> Enum.find(fn {{type, _id}, meta} ->
        type == "roll" and meta["target_type"] == type_id
      end)

    unless roll_def do
      raise "No roll defined for concept type \"#{type_id}\" in system \"#{system.module.slug}\""
    end

    {_key, %{"dice" => dice_str, "bonus_field" => bonus_field}} = roll_def

    effects = active_effects(system, character)
    resolved = Evaluator.evaluate!(system, character.generated_values, effects)

    bonus_key = {type_id, concept_id, bonus_field}

    unless Map.has_key?(resolved, bonus_key) do
      raise "Concept \"#{type_id}('#{concept_id}')\" not found in system \"#{system.module.slug}\""
    end

    bonus = resolved[bonus_key]
    rolls = Dice.roll(dice_str)

    %{
      type_id: type_id,
      concept_id: concept_id,
      dice: dice_str,
      rolls: rolls,
      bonus: bonus,
      total: Enum.sum(rolls) + bonus
    }
  end

  defp root_concept_ids(concept_metadata, type_id) do
    all_ids =
      concept_metadata
      |> Enum.filter(fn {{t, _}, _} -> t == type_id end)
      |> Enum.map(fn {{_, id}, _} -> id end)

    sub_ids =
      concept_metadata
      |> Enum.flat_map(fn {_, meta} -> sub_option_ids(meta, type_id) end)
      |> MapSet.new()

    Enum.reject(all_ids, &MapSet.member?(sub_ids, &1))
  end

  defp random_sub_decisions(concept_metadata, {type_id, concept_id} = key) do
    concept_metadata
    |> Map.get(key, %{})
    |> Map.get("choices", %{})
    |> Enum.flat_map(fn {choice_id, choice_def} ->
      sub_type = choice_def["type"]
      selected = Enum.random(choice_def["options"])
      decision = %{scope: {type_id, concept_id}, choice: choice_id, selection: selected}
      [decision | random_sub_decisions(concept_metadata, {sub_type, selected})]
    end)
  end

  defp sub_option_ids(meta, type_id) do
    meta
    |> Map.get("choices", %{})
    |> Enum.flat_map(fn {_, choice_def} ->
      if choice_def["type"] == type_id, do: choice_def["options"] || [], else: []
    end)
  end

  defp collect_active_concepts({_type, _id} = key, decisions, concept_metadata, acc) do
    acc = MapSet.put(acc, key)
    choices = concept_metadata |> Map.get(key, %{}) |> Map.get("choices", %{})

    Enum.reduce(choices, acc, fn {choice_id, choice_def}, acc ->
      decision = Enum.find(decisions, &(&1.scope == key and &1.choice == choice_id))

      if decision do
        collect_active_concepts(
          {choice_def["type"], decision.selection},
          decisions,
          concept_metadata,
          acc
        )
      else
        acc
      end
    end)
  end
end
