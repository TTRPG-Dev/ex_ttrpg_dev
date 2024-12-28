defmodule ExTTRPGDev.CLI.CustomParsers do
  @moduledoc """
  Custom parsers to be used with Optimus args :parse
  """
  alias ExTTRPGDev.RuleSystems

  @doc """
  Parses a string of dice specifications seperated by commas

  ## Examples

      iex> ExTTRPGDev.CLI.CustomParsers.dice_parser("3d4, 1d10,2d20")
      {:ok, ["3d4", "1d10", "2d20"]}
  """
  def dice_parser(arg) when is_bitstring(arg) do
    arg
    |> String.split(",")
    |> Enum.map(&String.trim(&1))
    |> Kernel.then(fn result -> {:ok, result} end)
  end

  @doc """
  Loads the rule system for the given system name

  ## Examples

      iex> ExTTRPGDev.CLI.CustomParsers.system_parser("dnd_5e_srd")
      {:ok, %ExTTRPGDev.RuleSystems.RuleSystem{}}
  """
  def system_parser(system) when is_bitstring(system) do
    if RuleSystems.is_configured?(system) do
      system
      |> RuleSystems.load_system!()
      |> Kernel.then(fn result -> {:ok, result} end)
    else
      {:error,
       "\"#{system}\" is not configured, run `ex_ttrpg_dev systems list` to list configured systems"}
    end
  end
end
