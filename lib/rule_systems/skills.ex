defmodule ExTTRPGDev.RuleSystems.Skills do
  @moduledoc """
  This module handles the definition of rule system skills and caclulating
  their modifiers
  """

  defmodule Skill do
    @moduledoc """
    The specific definition of a skill
    """
    defstruct [:name, :modifying_stat, :description, :examples]
  end
end
