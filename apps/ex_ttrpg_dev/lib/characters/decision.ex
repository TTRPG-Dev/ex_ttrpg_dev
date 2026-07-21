defmodule ExTTRPGDev.Characters.Decision do
  @moduledoc """
  A single choice recorded on a character.

  - `:scope` — `nil` for root character-building choices (race, class, ...);
    `{type_id, concept_id}` for a choice declared by that concept, including
    progression scopes (`{"character_progression", progression_id}`).
  - `:choice` — the choice identifier within the scope: a concept type ID at
    root scope, a declared choice key or canonical progression choice ID
    (`"choice_N"`) otherwise.
  - `:selection` — the selected concept ID, or a value-method label for value
    progressions (e.g. `"rolled"`).
  """

  @type scope :: nil | {String.t(), String.t()}

  @type t :: %__MODULE__{
          scope: scope(),
          choice: String.t(),
          selection: String.t()
        }

  defstruct [:scope, :choice, :selection]

  @doc "Builds a decision."
  def new(scope, choice, selection),
    do: %__MODULE__{scope: scope, choice: choice, selection: selection}

  @doc """
  Encodes a decision for character JSON. A `nil` scope stays `null`; a
  `{type, id}` scope is encoded as `"type:id"`.
  """
  def to_json_map(%__MODULE__{scope: nil, choice: choice, selection: selection}) do
    %{"scope" => nil, "choice" => choice, "selection" => selection}
  end

  def to_json_map(%__MODULE__{scope: {type, id}, choice: choice, selection: selection}) do
    %{"scope" => "#{type}:#{id}", "choice" => choice, "selection" => selection}
  end

  @doc "Decodes a decision from its character-JSON map form."
  def from_json_map(%{"scope" => nil, "choice" => choice, "selection" => selection}) do
    %__MODULE__{scope: nil, choice: choice, selection: selection}
  end

  def from_json_map(%{"scope" => scope_str, "choice" => choice, "selection" => selection}) do
    [type, id] = String.split(scope_str, ":", parts: 2)
    %__MODULE__{scope: {type, id}, choice: choice, selection: selection}
  end
end
