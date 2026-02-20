defmodule ExTTRPGDev.CLI.Characters do
  @moduledoc """
  Definitions for dealing with character CLI commands
  """
  alias ExTTRPGDev.Characters.Character
  alias ExTTRPGDev.CLI.Args
  alias ExTTRPGDev.CLI.CharacterDisplay
  alias ExTTRPGDev.CLI.Inputs
  alias ExTTRPGDev.RuleSystems
  alias ExTTRPGDev.RuleSystems.LoadedSystem

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
                help: "If specified, saves the character",
                multiple: false
              ]
            ]
          ],
          list: [
            name: "list",
            about: "List saved characters"
          ],
          show: [
            name: "show",
            about: "Show information for a character",
            args: Args.character()
          ]
        ]
      ]
    ]
  end

  @doc """
  Handle `characters` CLI command and sub commands
  """
  def handle_characters_subcommands([:gen | _subcommands], %Optimus.ParseResult{
        args: %{system: %LoadedSystem{} = system},
        flags: %{save: save_character_flag}
      }) do
    character = Character.gen_character!(system)

    CharacterDisplay.print(system, character)

    if save_character_flag or Inputs.get_yes_no!("Would you like to save this character?") do
      ExTTRPGDev.Characters.save_character!(character)
    end
  end

  def handle_characters_subcommands([:list | _subcommands], _args_options_flags) do
    case ExTTRPGDev.Characters.list_characters!() do
      [] ->
        IO.puts("No saved characters found!")

      characters ->
        IO.puts("Saved Characters:")
        Enum.each(characters, fn character -> IO.puts("- #{character}") end)
    end
  end

  def handle_characters_subcommands([:show | _subcommands], %Optimus.ParseResult{
        args: %{character: character}
      }) do
    system = RuleSystems.load_system!(character.metadata.rule_system)
    CharacterDisplay.print(system, character)
  end
end
