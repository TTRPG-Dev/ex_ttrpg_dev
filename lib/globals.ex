defmodule ExTTRPGDev.Globals do
  @moduledoc """
  Module which defines globals like project paths
  """
  @license_file_name "license.md"
  @toml_file_pattern ~r/.+\.toml$/

  @doc """
  The path to where bundled system configs are stored.
  Resolved at runtime using the application's priv directory.

  ## Examples
    iex> ExTTRPGDev.Globals.system_configs_path() |> String.ends_with?("system_configs")
    true

  """
  def system_configs_path do
    cwd_path = Path.join(File.cwd!(), "priv/system_configs")

    if File.exists?(cwd_path) do
      cwd_path
    else
      :code.priv_dir(:ex_ttrpg_dev)
      |> to_string()
      |> Path.join("system_configs")
    end
  end

  @doc """
  The path to where custom (local) rule system configs are stored.
  Resolved at runtime relative to the current working directory.

  ## Examples
    iex> ExTTRPGDev.Globals.local_system_configs_path() |> String.ends_with?("local_system_configs")
    true

  """
  def local_system_configs_path do
    Path.join(File.cwd!(), "local_system_configs")
  end

  @doc """
  The path to where characters are stored.
  Resolved at runtime relative to the current working directory.

  ## Examples
    iex> ExTTRPGDev.Globals.characters_path() |> String.ends_with?("local_characters")
    true

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
