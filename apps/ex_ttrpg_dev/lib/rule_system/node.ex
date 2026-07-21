defmodule ExTTRPGDev.RuleSystem.Node do
  @moduledoc """
  A single node in a rule system's evaluation DAG.

  The `:type` field determines which other fields are meaningful:

  - `:generated` — leaf value rolled at character generation; `:method` names
    the rolling method (`nil` falls back to the system default).
  - `:accumulator` — `:base` formula plus the sum of contributed effects.
  - `:formula` — `:formula` expression evaluated against resolved nodes.
  - `:mapping` — `:input` expression looked up in `:steps`
    (`[[threshold, value], ...]`, thresholds ascending; the value of the last
    step whose threshold is <= the input wins).
  """

  @type node_type :: :generated | :accumulator | :formula | :mapping

  @type t :: %__MODULE__{
          type: node_type(),
          method: String.t() | nil,
          base: String.t() | nil,
          formula: String.t() | nil,
          input: String.t() | nil,
          steps: [[number()]] | nil
        }

  defstruct [:type, :method, :base, :formula, :input, :steps]
end
