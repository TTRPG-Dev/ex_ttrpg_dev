# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI.Characters do
  @moduledoc """
  Defintions for dealing with character CLI commands
  """
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.CLI.Args

  @doc """
  Command specifications for character CLI commands
  """
  def commands do
    [
      characters: [
        name: "characters",
        about: "Top level command for characters",
        subcommands: [
          gen: [
            name: "gen",
            about: "Generate a character for a system",
            args: Args.system()
          ]
        ]
      ]
    ]
  end

  @doc """
  Handle `characters` CLI command and sub commands
  """
  def handle_characters_subcommands([:gen | _subcommands], %Optimus.ParseResult{
        args: %{system: system}
      }) do
    character =
      system
      |> ExTTRPGDev.RuleSystems.assert_configured!()
      |> ExTTRPGDev.RuleSystems.load_system!()
      |> Character.gen_character!()

    IO.puts("-- Name: #{character.name}")

    Enum.each(character.ability_scores, fn {ability, scores} ->
      IO.puts("#{ability}: #{Enum.sum(scores)}")
    end)
  end
end
