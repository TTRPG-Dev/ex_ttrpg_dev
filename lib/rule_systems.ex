defmodule ExRPG.RuleSystems do
  alias ExRPG.RuleSystems
  alias ExRPG.Globals
  alias ExRPG.RuleSystems.RuleSystem

  @moduledoc """
  Module which enables interactions with the varying defined systems in the
  system_configs. Basically sytem_configs define what systems are available and
  how they should be interpreted, and this module is is the beginning of the
  interpretation.
  """

  @doc """
  List the systems available

  ## Examples

      iex> ExRPG.RuleSystems.list_systems()
      ["dnd_5e_srd"]
  """
  def list_systems do
    File.ls!(Globals.system_configs_path())
  end

  @doc """
  Checks if the given system is configured.
  Returns true if system is configured, otherwise false.

  ## Examples
      iex> ExRPG.RuleSystems.is_configured?("dnd_5e_srd")
      true

      iex> ExRPG.RuleSystems.is_configured?("non_existent_system")
      false
  """
  def is_configured?(system) when is_bitstring(system) do
    list_systems()
    |> Enum.any?(fn configured_systems -> configured_systems == system end)
  end

  @doc """
  Ensures a system is configured. If the system is configured, the system name
  is returned. If the system isn't configured, an exception is raised.
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
      iex> ExRPG.RuleSystems.system_path!("dnd_5e_srd")
      "/full/path/to/project/ex_rpg/system_configs/dnd_5e_srd"
  """
  def system_path!(system) when is_bitstring(system) do
    Path.join([Globals.system_configs_path(), system])
  end

  @doc """
  Reads in all of the JSON files for the specified and decodes
  the json into a %Systems{} struct

  ## Examples

      iex> ExRPG.RuleSystems.load_system!("dnd_5e_srd")
      %ExRPG.RuleSystems.RuleSystem{}

  """
  def load_system!(system) when is_bitstring(system) do
    system_path = ExRPG.RuleSystems.system_path!(system)

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
end
