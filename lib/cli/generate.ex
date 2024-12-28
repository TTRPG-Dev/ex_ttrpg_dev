# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI.Generate do
  @moduledoc """
  Definitions for dealing with genenerate CLI commands
  """
  alias ExTTRPGDev.CLI.Args
  alias ExTTRPGDev.RuleSystems.RuleSystem

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
        args: %{system: system}
      }) do
    RuleSystem.gen_ability_scores_assigned(system)
    |> IO.inspect()
  end
end
