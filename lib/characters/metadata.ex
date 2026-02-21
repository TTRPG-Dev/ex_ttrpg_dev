defmodule ExTTRPGDev.Characters.Metadata do
  @moduledoc """
  Metadata for an individual character.
  """
  defstruct [:slug, :rule_system]
  # rule_system is a String.t() slug, e.g. "dnd_5e_srd"
end
