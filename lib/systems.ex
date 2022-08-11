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
end
