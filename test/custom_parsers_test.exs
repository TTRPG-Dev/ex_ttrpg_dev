defmodule ExTTRPGDevTest.CLI.CustomParsers do
  use ExUnit.Case

  alias ExTTRPGDev.CLI.CustomParsers
  alias ExTTRPGDev.RuleSystems.RuleSystem

  doctest ExTTRPGDev.CLI.CustomParsers,
    except: [
      system_parser: 1
    ]

  def system_parser_test do
    # If no error was raised, then all is good
    {:ok, %RuleSystem{}} = CustomParsers.system_parser("dnd_5e_srd")

    # Should raise an error
    assert_raise RuntimeError, CustomParsers.system_parser("unknown_system")
  end
end
