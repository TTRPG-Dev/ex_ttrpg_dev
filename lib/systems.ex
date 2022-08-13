defmodule ExRPG.Systems do
  alias ExRPG.Globals

  @moduledoc """
  Module which enables interactions with the varying defined systems in the
  system_configs. Basically sytem_configs define what systems are available and
  how they should be interpreted, and this module is is the beginning of the
  interpretation.
  """

  @doc """
  List the systems available

  ## Examples

      iex> ExRPG.Systems.list_systems()
      ["dnd_5e_srd"]
  """
  def list_systems do
    File.ls!(Globals.system_configs_path())
  end

  @doc """
  Checks if the given system is configured.
  Returns true if system is configured, otherwise false.

  ## Examples
      iex> ExRPG.Systems.is_configured?("dnd_5e_srd")
      true

      iex> ExRPG.Systems.is_configured?("non_existent_system")
      false
  """
  def is_configured?(system) when is_bitstring(system) do
    list_systems()
    |> Enum.any?(fn configured_systems -> configured_systems == system end)
  end

  @doc """
  Returns the path to to the systems config directory

  ## Examples
      iex> ExRPG.systems.system_path!("dnd_5e_srd")
      "/full/path/to/project/ex_rpg/system_configs/dnd_5e_srd"
  """
  def system_path!(system) when is_bitstring(system) do
    Path.join([Globals.system_configs_path, system])
  end
end
