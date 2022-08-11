defmodule ExRPG.Globals do
  @moduledoc """
  Module which defines globals like project paths
  """
  @project_root File.cwd!
  @system_configs_path Path.join(~w(#{@project_root} system_configs))

  @doc """
  The path to where the project lives on your machine

  ## Examples

      iex> ExRPG.Globals.project_root()
      "/full/path/to/project/ex_rpg"

  """
  def project_root do
    @project_root
  end

  @doc """
  The path to where system configs are stored

  ## Examples

      iex> ExRPG.Globals.system_configs_path()
      "/full/path/to/project/ex_rpg/system_configs"

  """
  def system_configs_path do
    @system_configs_path
  end
end