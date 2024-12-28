defmodule ExTTRPGDev.CLI.Args do
  @moduledoc """
  Defines common CLI args
  """

  def system do
    [
      system: [
        value_name: "SYSTEM",
        help: "A supported system, e.g. basic_fantasy_4e",
        required: true,
        parser: :string
      ]
    ]
  end
end
