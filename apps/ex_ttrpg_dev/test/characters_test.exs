defmodule ExTTRPGDevTest.Characters do
  # The Characters module is a thin facade; its behavior is tested per
  # concern in test/characters/*_test.exs. This module only runs the
  # facade's doctests.
  use ExUnit.Case, async: true

  doctest ExTTRPGDev.Characters,
    except: [
      character_file_path!: 1,
      character_exists?: 1,
      save_character!: 1,
      save_character!: 2,
      list_characters!: 0,
      load_character!: 1,
      concept_roll!: 4
    ]
end
