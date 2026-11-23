defmodule ExTTRPGDev.CLI.ServerStartupTest do
  # Not async: replaces the global :default logger handler and writes to
  # the suite-wide rule system store.
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

  test "sync_rule_systems/0 installs bundled systems into the store" do
    ExUnit.CaptureLog.capture_log(fn -> assert :ok = Server.sync_rule_systems() end)

    assert Enum.any?(
             ExTTRPGDev.RuleSystems.list_installed_systems!(),
             &(&1.slug == "dnd_5e_srd" and not &1.is_modifiable)
           )
  end
end
