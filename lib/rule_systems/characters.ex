defmodule ExTTRPGDev.RuleSystems.Characters do
  @moduledoc """
  This module handles the definition of rule system characters, and what they do
  """

  defmodule CharacterMetadata do
    @moduledoc """
    Metadata for an individual charater
    """
    defstruct [:slug, :rule_system]
  end

  defmodule Character do
    @moduledoc """
    Definition of an individual character
    """
    defstruct [:name, :ability_scores, :metadata]
  end
end
