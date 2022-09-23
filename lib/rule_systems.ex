defmodule ExTTRPGDev.RuleSystems do
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.RuleSystems.RuleSystem

  @moduledoc """
  Module which enables interactions with the varying defined systems in the
  system_configs. Basically sytem_configs define what systems are available and
  how they should be interpreted, and this module is is the beginning of the
  interpretation.
  """

  @doc """
  List the systems available

  ## Examples

      iex> ExTTRPGDev.RuleSystems.list_systems()
      ["dnd_5e_srd"]
  """
  def list_systems do
    list_bundled_systems() ++ list_local_systems()
  end

  @doc """
  List the ExTTRPGDev local custom systems available

  ## Examples

      iex> ExTTRPGDev.RuleSystems.list_bundled_systems()
      ["dnd_5e_srd"]
  """
  def list_bundled_systems do
    File.ls!(Globals.system_configs_path())
  end

  @doc """
  List the ExTTRPGDev bundled systems available

  ## Examples

      iex> ExTTRPGDev.RuleSystems.list_local_systems()
      []
  """
  def list_local_systems do
    if File.exists?(Globals.local_system_configs_path()) do
      File.ls!(Globals.local_system_configs_path())
    else
      []
    end
  end

  @doc """
  Checks if the given system is a bundled system

  ## Examples

      iex> ExTTRPGDev.RuleSystems.is_bundled_system?("dnd_5e_srd")
      true

      iex> ExTTRPGDev.RuleSystems.is_bundled_system?("my_custom_rule_system")
      false
  """
  def is_bundled_system?(system) when is_bitstring(system) do
    list_bundled_systems()
    |> Enum.any?(fn configured_system -> configured_system == system end)
  end

  @doc """
  Checks if the given system is a local system

  ## Examples

      iex> ExTTRPGDev.RuleSystems.is_local_system?("dnd_5e_srd")
      false

      iex> ExTTRPGDev.RuleSystems.is_local_system?("my_custom_rule_system")
      true
  """
  def is_local_system?(system) when is_bitstring(system) do
    list_local_systems()
    |> Enum.any?(fn configured_system -> configured_system == system end)
  end

  @doc """
  Checks if the given system is configured.
  Returns true if system is configured, otherwise false.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.is_configured?("dnd_5e_srd")
      true

      iex> ExTTRPGDev.RuleSystems.is_configured?("non_existent_system")
      false
  """
  def is_configured?(system) when is_bitstring(system) do
    list_systems()
    |> Enum.any?(fn configured_systems -> configured_systems == system end)
  end

  @doc """
  Ensures a system is configured. If the system is configured, the system name
  is returned. If the system isn't configured, an exception is raised.

  ## Examples
      iex> ExTTRPGDev.RuleSystems.assert_configured!("dnd_5e_srd")
      "dnd_5e_srd"

      iex> ExTTRPGDev.RuleSystems.assert_configured!("not_configured")
      ** (RuntimeError) System `not_configured` is not congifured
  """
  def assert_configured!(system) when is_bitstring(system) do
    if RuleSystems.is_configured?(system) do
      system
    else
      raise "System `#{system}` is not congifured"
    end
  end

  @doc """
  Returns the path to to the systems config directory

  ## Examples
      iex> ExTTRPGDev.RuleSystems.system_path!("dnd_5e_srd")
      "/full/path/to/project/ex_rpg/system_configs/dnd_5e_srd"
  """
  def system_path!(system) when is_bitstring(system) do
    if is_bundled_system?(system) do
      Path.join([Globals.system_configs_path(), system])
    else
      Path.join([Globals.local_system_configs_path(), system])
    end
  end

  @doc """
  Reads in all of the JSON files for the specified and decodes
  the json into a %Systems{} struct

  ## Examples

      iex> ExTTRPGDev.RuleSystems.load_system!("dnd_5e_srd")
      %ExTTRPGDev.RuleSystems.RuleSystem{}

  """
  def load_system!(system) when is_bitstring(system) do
    system_path = ExTTRPGDev.RuleSystems.system_path!(system)

    File.ls!(system_path)
    |> Enum.filter(fn file_name -> Regex.match?(Globals.json_file_pattern(), file_name) end)
    |> Enum.reduce(%{}, fn file, acc ->
      Path.join(system_path, file)
      |> File.read!()
      |> Poison.decode!()
      |> Map.merge(acc)
    end)
    |> Poison.encode!()
    |> RuleSystem.from_json!()
  end

  @doc """
  Saves the system specification locally as a JSON file. If a system is a
  bundled config, an exception is raised. If the system already exists and
  `overwrite` wasn't specificed as true, an exception is raised.

  ## Examples

      iex> ExTTRPGDev>RuleSystems.save_system!(%ExTTRPGDev.RuleSystems.RuleSystem{})
      :ok

      iex> ExTTRPGDev>RuleSystems.save_system!(%ExTTRPGDev.RuleSystems.RuleSystem{})
      :error, :config_already_exists

      iex> ExTTRPGDev>RuleSystems.save_system!(%ExTTRPGDev.RuleSystems.RuleSystem{}, true)
      :ok
  """
  def save_system!(
        %RuleSystem{metadata: %RuleSystems.Metadata{slug: system_slug}} = system,
        overwrite \\ false
      ) do
    cond do
      is_bundled_system?(system_slug) ->
        raise "System `#{system_slug}` is a bundled config. Please change system's name and slug before saving."

      not is_local_system?(system_slug) or overwrite ->
        system_path = system_path!(system_slug)

        # if `overwrite` delete system dir
        # also... this seems incredibly dangerous
        if overwrite do
          File.rm_rf!(system_path)
        end

        # create the dir if it doesn't exist
        File.mkdir_p!(system_path)
        # write the system config to file
        File.write!(Path.join(system_path, "system.json"), Poison.encode!(system), [:binary])

      true ->
        raise "System already exists. To overwrite, pass `overwrite` as true"
    end
  end
end
