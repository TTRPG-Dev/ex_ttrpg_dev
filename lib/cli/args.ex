defmodule ExTTRPGDev.CLI.Args do
  @moduledoc """
  Defines common CLI args
  """
  alias ExTTRPGDev.CLI.CustomParsers

  @doc """
  Argument spec for any command needing to take in the name of a rule system
  """
  def system do
    [
      system: [
        value_name: "SYSTEM",
        help: "A supported system, e.g. basic_fantasy_4e",
        required: true,
        parser: &CustomParsers.system_parser(&1)
      ]
    ]
  end

  def character do
    [
      character: [
        value_name: "CHARACTER",
        help: "A saved character, e.g. misu_park",
        required: true,
        parser: &CustomParsers.character_parser(&1)
      ]
    ]
  end
end
