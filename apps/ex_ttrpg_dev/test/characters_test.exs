defmodule ExTTRPGDevTest.Characters do
  # The Characters module is a thin facade; its behavior is tested per
  # concern in test/characters/*_test.exs. This module only runs the
  # facade's doctests.
  use ExUnit.Case, async: true

  doctest ExTTRPGDev.Characters,
    except: [
      # Rolls dice and requires a loaded rule system with a domain-specific
      # roll definition configured — not reproducible deterministically here.
      concept_roll!: 4
    ]
end
