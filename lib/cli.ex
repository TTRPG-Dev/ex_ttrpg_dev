# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI do
  alias ExTTRPGDev.CLI.Generate
  alias ExTTRPGDev.CLI.Roll
  alias ExTTRPGDev.CLI.RuleSystems

  @moduledoc """
  The CLI for the project
  """

  def main(argv) do
    optimus =
      Optimus.new!(
        name: "ex_ttrpg_dev",
        description: "CLI for all things RPG",
        version: "0.5.0",
        author: "Quigley Malcolm quigley@quigleymalcolm.com",
        about: "Utility for playing tabletop role-playing games.",
        allow_unknown_args: false,
        parse_double_dash: true,
        subcommands:
          Roll.commands() ++
            RuleSystems.commands() ++
            Generate.commands()
      )

    case Optimus.parse!(optimus, argv) do
      %{args: %{}} ->
        Optimus.parse!(optimus, ["--help"])

      {[:roll], parse_result} ->
        Roll.handle(parse_result)

      {[:list_systems], _} ->
        RuleSystems.handle_list_systems()

      {[:systems | sub_commands], parse_result} ->
        RuleSystems.handle_systems_subcommands(sub_commands, parse_result)

      {[:gen | sub_commands], _} ->
        Generate.handle_generate_subcommands(sub_commands)

      {unhandled, _parse_result} ->
        str_command =
          unhandled
          |> Enum.reduce([], fn x, acc -> [Atom.to_string(x) | acc] end)
          |> Enum.reverse()
          |> Enum.join(" ")

        raise "Unhandled CLI command `#{str_command}`, if you are seeing this error please report the issue"
    end
  end
end
