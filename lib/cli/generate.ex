# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI.Generate do
  @moduledoc """
  Definitions for dealing with genenerate CLI commands
  """

  @doc """
  Command specifications for generate commands
  """
  def commands do
    [
      gen: [
        name: "gen",
        about: "system agnostic generation helpers",
        subcommands: [
          name: [
            name: "name",
            about: "Generate a random name"
          ]
        ]
      ]
    ]
  end

  @doc """
  Handles generate sub commands
  """
  def handle_generate_subcommands([command | _subcommands]) do
    case command do
      :name ->
        IO.inspect(Faker.Person.name())
    end
  end
end
