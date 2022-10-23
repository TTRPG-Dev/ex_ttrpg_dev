defmodule ExTTRPGDev.RuleSystems.Languages do
  @moduledoc """
  This module handles the definition of rule system languages
  """

  defmodule Language do
    @moduledoc """
    Definition of an individual language
    """
    defstruct [:name, :script]
  end
end
