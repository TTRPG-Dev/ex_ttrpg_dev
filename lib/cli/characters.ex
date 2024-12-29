# credo:disable-for-this-file Credo.Check.Warning.IoInspect
defmodule ExTTRPGDev.CLI.Characters do
  @moduledoc """
  Defintions for dealing with character CLI commands
  """
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.CLI.Args
  alias ExTTRPGDev.CLI.Inputs

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
            args: Args.system(),
            flags: [
              save: [
                short: "-s",
                long: "--save",
                help: "If specidied, saves the character",
                multiple: false
              ]
            ]
          ]
        ]
      ]
    ]
  end

  @doc """
  Handle `characters` CLI command and sub commands
  """
  def handle_characters_subcommands([:gen | _subcommands], %Optimus.ParseResult{
        args: %{system: system},
        flags: %{save: save_character_flag}
      }) do
    character = system |> Character.gen_character!()

    IO.puts("-- Name: #{character.name}")

    Enum.each(character.ability_scores, fn {ability, scores} ->
      IO.puts("#{ability}: #{Enum.sum(scores)}")
    end)

    if save_character_flag or Inputs.get_yes_no!("Would you like to save this character?") do
      ExTTRPGDev.Characters.save_character!(character)
    end
  end
end
