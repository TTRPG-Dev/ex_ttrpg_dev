defmodule ExTTRPGDev.RuleSystems.LoadedSystem do
  @moduledoc """
  Represents a fully loaded and validated rule system, ready for evaluation.

  Produced by `ExTTRPGDev.RuleSystems.load_system!/1`.
  """
  defstruct [:package, :graph, :nodes, :rolling_methods, :entity_metadata, :contributions]
end
