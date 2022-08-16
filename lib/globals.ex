defmodule ExRPG.Globals do
  @moduledoc """
  Module which defines globals like project paths
  """
  @project_root File.cwd!
  @system_configs_path Path.join(~w(#{@project_root} priv system_configs))
  @license_file_name "license.md"
  @json_file_pattern ~r/.+\.json$/

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

  @doc """
  The name for license files

  ## Examples
    iex> ExRPG.Globals.license_file_name()
    "license.md"

  """
  def license_file_name do
    @license_file_name
  end

  @doc """
  The regex pattern for identifying json files

  ## Examples
    iex> ExRPG.Globals.json_file_name()
    ~r/.+\\.json$/
  """
  def json_file_pattern do
    @json_file_pattern
  end
end
