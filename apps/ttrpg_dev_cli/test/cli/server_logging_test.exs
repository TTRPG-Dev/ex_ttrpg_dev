defmodule ExTTRPGDev.CLI.ServerLoggingTest do
  # Not async: replaces the global :default logger handler.
  use ExUnit.Case
  alias ExTTRPGDev.CLI.Server

  setup do
    {:ok, original} = :logger.get_handler_config(:default)

    on_exit(fn ->
      :logger.remove_handler(:default)
      :logger.add_handler(:default, original.module, Map.drop(original, [:id, :module]))
    end)
  end

  test "log_to_stderr/0 moves the default handler off stdout, idempotently" do
    assert :ok = Server.log_to_stderr()
    assert :ok = Server.log_to_stderr()
    assert {:ok, %{config: %{type: :standard_error}}} = :logger.get_handler_config(:default)
  end
end
