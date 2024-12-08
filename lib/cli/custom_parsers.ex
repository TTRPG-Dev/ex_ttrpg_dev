defmodule ExTTRPGDev.CLI.CustomParsers do
  @moduledoc """
  Custom parsers to be used with Optimus args :parse
  """

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
end
