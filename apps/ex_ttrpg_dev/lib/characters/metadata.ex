defmodule ExTTRPGDev.Characters.Metadata do
  @moduledoc """
  Metadata for an individual character.

  - `slug` — the character's own identifier.
  - `rule_system` — slug of the rule system the character was built with,
    e.g. `"dnd_5e_srd"`.
  - `rule_system_version` — that system's content `version` at the time the
    character was generated, so that which characters depend on a given
    `{slug, version}` is answerable. `nil` for characters saved before this
    field existed; such characters are treated as depending on every
    version of their system.
  """
  defstruct [:slug, :rule_system, :rule_system_version]

  @type t :: %__MODULE__{
          slug: String.t() | nil,
          rule_system: String.t() | nil,
          rule_system_version: String.t() | nil
        }
end
