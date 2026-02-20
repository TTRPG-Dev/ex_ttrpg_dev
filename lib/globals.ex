defmodule ExTTRPGDev.Globals do
  @moduledoc """
  Module which defines globals like project paths
  """
  @license_file_name "license.md"
  @toml_file_pattern ~r/.+\.toml$/

  @doc """
  The path to where bundled system configs are stored.
  Resolved at runtime using the application's priv directory.
  """
  def system_configs_path do
    Application.app_dir(:ex_ttrpg_dev, "priv/system_configs")
  end

  @doc """
  The path to where custom (local) rule system configs are stored.
  Resolved at runtime relative to the current working directory.
  """
  def local_system_configs_path do
    Path.join(File.cwd!(), "local_system_configs")
  end

  @doc """
  The path to where characters are stored.
  Resolved at runtime relative to the current working directory.
  """
  def characters_path do
    Path.join(File.cwd!(), "local_characters")
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
  The regex pattern for identifying toml files

  ## Examples
    iex> "system_config.toml" =~ ExTTRPGDev.Globals.toml_file_pattern()
    true

    iex> "not_a_toml" =~ ExTTRPGDev.Globals.toml_file_pattern()
    false
  """
  def toml_file_pattern do
    @toml_file_pattern
  end
end
