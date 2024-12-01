defmodule ExTTRPGDev.RuleSystems.Characters do
  @moduledoc """
  This module handles the definition of rule system characters, and what they do
  """

  defmodule Character do
    @moduledoc """
    Definition of an individual character
    """
    defstruct [:name, :ability_scores, :rule_system]
  end
end
