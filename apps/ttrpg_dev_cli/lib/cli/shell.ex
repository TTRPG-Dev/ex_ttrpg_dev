defmodule ExTTRPGDev.CLI.Shell do
  @moduledoc """
  Interactive REPL shell for ttrpg-dev.
  Launched when the binary is invoked with no arguments.
  """

  @prompt "ttrpg-dev> "

  defmodule HaltSignal do
    defexception [:code, message: "halt requested in shell mode"]
  end

  def run(optimus) do
    IO.puts(banner())
    loop(optimus)
  end

  defp loop(optimus) do
    case IO.gets(@prompt) do
      :eof ->
        IO.puts("\nGoodbye!")

      {:error, reason} ->
        IO.puts("Input error: #{inspect(reason)}")

      line when is_binary(line) ->
        case line |> String.trim() |> handle_input(optimus) do
          :exit -> IO.puts("Goodbye!")
          :continue -> loop(optimus)
        end
    end
  end

  defp handle_input("", _optimus), do: :continue

  defp handle_input(cmd, _optimus) when cmd in ["exit", "quit"], do: :exit

  defp handle_input("help", _optimus) do
    IO.puts("""
    Commands (same syntax as the CLI):
      roll <dice>              Roll dice, e.g. roll 3d6
      systems list             List configured rule systems
      systems show <cmd>       Show system info (abilities/languages/metadata/skills)
      gen name                 Generate a random name
      gen stat-block <system>  Generate a stat block
      characters gen <system>  Generate a character
      characters list          List saved characters
      characters show <slug>   Show a saved character
      help                     Show this help
      exit / quit              Exit the shell
    """)

    :continue
  end

  defp handle_input(input, optimus) do
    tokens = OptionParser.split(input)

    try do
      ExTTRPGDev.CLI.dispatch(tokens, optimus, &shell_halt/1)
    rescue
      e in HaltSignal ->
        if e.code != 0, do: IO.puts("(Use `help` to see available commands)")

      e ->
        IO.puts("Error: #{Exception.message(e)}")
    end

    :continue
  end

  defp shell_halt(code), do: raise(HaltSignal, code: code)

  defp banner do
    """
    TTRPG Dev — interactive shell
    Type `help` for available commands, `exit` to quit.
    """
  end
end
