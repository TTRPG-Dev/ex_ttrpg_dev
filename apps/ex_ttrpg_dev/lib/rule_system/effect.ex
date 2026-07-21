defmodule ExTTRPGDev.RuleSystem.Effect do
  @moduledoc """
  A contribution to an accumulator node.

  - `:source` — `{type_id, concept_id}` of the concept that declared the
    effect, or `nil` for effects the character carries directly (awards,
    rolled values). Only effects whose source concept is active apply.
  - `:target` — `{type_id, concept_id, field_name}` node key the value
    contributes to.
  - `:value` — a number, or a formula string evaluated against resolved
    nodes (with `item.<field>` placeholders substituted from
    `:item_fields`).
  - `:when` — optional condition formula; the effect applies only when it
    evaluates truthy.
  - `:item_fields` — field map of the inventory item that granted this
    effect (`%{}` otherwise); the substitution source for `item.<field>`
    references in `:value` and `:when`.
  """

  @type node_key :: {String.t(), String.t(), String.t()}

  @type t :: %__MODULE__{
          source: {String.t(), String.t()} | node_key() | nil,
          target: node_key(),
          value: number() | String.t(),
          when: String.t() | nil,
          item_fields: %{optional(String.t()) => term()}
        }

  defstruct [:source, :target, :value, :when, item_fields: %{}]
end
