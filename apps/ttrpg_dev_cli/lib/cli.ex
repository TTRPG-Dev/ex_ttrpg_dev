defmodule ExTTRPGDev.CLI do
  @moduledoc """
  Entry point for the ttrpg-dev-engine binary.

  In normal operation this binary is driven by the Rust CLI frontend
  (`ttrpg-dev`) via the `--server` flag, which starts the JSON server
  mode. Direct invocation with no arguments prints a brief usage note.
  """

  alias ExTTRPGDev.CLI.Server

  def main(["--server"]), do: Server.run()

  def main(_argv) do
    IO.puts("ttrpg-dev-engine: backend engine for ttrpg-dev.")
    IO.puts("Run via the ttrpg-dev frontend, or pass --server to start JSON server mode.")
  end
end
