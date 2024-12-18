defmodule ExTTRPGDev.Globals do
  @moduledoc """
  Module which defines globals like project paths
  """
  @project_root File.cwd!()
  @characters_path Path.join(~w(#{@project_root} local_characters))
  @system_configs_path Path.join(~w(#{@project_root} priv system_configs))
  @local_system_configs_path Path.join(~w(#{@project_root} local_system_configs))
  @license_file_name "license.md"
  @json_file_pattern ~r/.+\.json$/

  @doc """
  The path to where the project lives on your machine

  ## Examples

      iex> ExTTRPGDev.Globals.project_root()
      "/full/path/to/project/ex_ttrpg_dev"

  """
  def project_root do
    @project_root
  end

  @doc """
  The path to where characters are stored on your machine

  ## Examples

      iex> ExTTRPGDev.Globals.characters_path()
      "/full/path/to/project/ex_ttrpg_dev/priv/characters"

  """
  def characters_path do
    @characters_path
  end

  @doc """
  The path to where system configs are stored

  ## Examples

      iex> ExTTRPGDev.Globals.system_configs_path()
      "/full/path/to/project/ex_ttrpg_dev/system_configs"

  """
  def system_configs_path do
    @system_configs_path
  end

  @doc """
  The path to where custom rule system configs are stored

  ## Examples

      iex> ExTTRPGDev.Globals.local_system_configs_path()
      "/full/path/to/project/ex_ttrpg_dev/local_system_configs"

  """
  def local_system_configs_path do
    @local_system_configs_path
  end

  @doc """
  The name for license files

  ## Examples
    iex> ExTTRPGDev.Globals.license_file_name()
    "license.md"

  """
  def license_file_name do
    @license_file_name
  end

  @doc """
  The regex pattern for identifying json files

  ## Examples
    iex> ExTTRPGDev.Globals.json_file_name()
    ~r/.+\\.json$/
  """
  def json_file_pattern do
    @json_file_pattern
  end
end
