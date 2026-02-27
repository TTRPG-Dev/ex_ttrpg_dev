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
              ],
              stat_block_only: [
                long: "--stat-block-only",
                help: "If specified, only prints the stat block without prompting to save",
                multiple: false
              ]
            ]
          ],
          list: [
            name: "list",
            about: "List saved characters",
            options: [
              system: [
                value_name: "SYSTEM",
                help: "Show all characters belonging to specific system",
                long: "--system",
                required: false
              ]
            ]
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
        flags: %{save: save_character_flag, stat_block_only: stat_block_only_flag}
      }) do
    character = Character.gen_character!(system)

    CharacterDisplay.print(system, character)

    unless stat_block_only_flag do
      if save_character_flag or Inputs.get_yes_no!("Would you like to save this character?") do
        ExTTRPGDev.Characters.save_character!(character)
      end
    end
  end

  def handle_characters_subcommands([:list | _subcommands], %Optimus.ParseResult{
        options: options
      }) do
    system = Map.get(options, :system)

    loaded_characters =
      ExTTRPGDev.Characters.list_characters!()
      |> Enum.map(fn character_slug -> ExTTRPGDev.Characters.load_character!(character_slug) end)

    filtered_characters =
      loaded_characters
      |> Enum.filter(fn character ->
        system == nil or character.metadata.rule_system == system
      end)

    cond do
      loaded_characters == [] ->
        IO.puts("No saved characters found!")

      filtered_characters == [] ->
        IO.puts("No saved characters found for system `#{system}`!")

      true ->
        filtered_characters
        |> Enum.each(fn character ->
          IO.puts(
            "- #{character.metadata.slug}: #{character.name} [#{character.metadata.rule_system}]"
          )
        end)
    end
  end

  def handle_characters_subcommands([:show | _subcommands], %Optimus.ParseResult{
        args: %{character: character}
      }) do
    system = RuleSystems.load_system!(character.metadata.rule_system)
    CharacterDisplay.print(system, character)
  end
end
