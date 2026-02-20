# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI.Generate do
  @moduledoc """
  Definitions for dealing with generate CLI commands
  """
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.CLI.Args
  alias ExTTRPGDev.RuleSystems.LoadedSystem

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
          ],
          stat_block: [
            name: "stat-block",
            about: "Generate stat blocks for characters of the system",
            args: Args.system()
          ]
        ]
      ]
    ]
  end

  @doc """
  Handles generate sub commands
  """
  def handle_generate_subcommands([:name | _subcommands], _parse_result),
    do: IO.inspect(Faker.Person.name())

  def handle_generate_subcommands([:stat_block | _subcommands], %Optimus.ParseResult{
        args: %{system: %LoadedSystem{} = system}
      }) do
    character = Character.gen_character!(system)

    IO.puts("-- Stat Block --")

    Enum.each(character.generated_values, fn {{type, id, _field}, value} ->
      name = get_in(system.entity_metadata, [{type, id}, "name"]) || id
      IO.puts("#{name}: #{value}")
    end)
  end
end
