defmodule ExTTRPGDev.RuleSystem.Vocabulary do
  @moduledoc """
  Single source of truth for the library's structural vocabulary — the
  reserved concept type IDs and metadata keys the library itself defines to
  interpret rule-system config.

  The *semantics* of every name are documented in the "Structural Vocabulary"
  section of `ExTTRPGDev.RuleSystem.Loader`. This module exists so each name
  is spelled exactly once in code: renaming or extending the vocabulary must
  never require a grep-sweep across the library.

  Consumers that need a name in a pattern-match position bind it to a module
  attribute at compile time (e.g. `@progression_type Vocabulary.progression_type()`).
  """

  @progression_type "character_progression"
  @roll_type "roll"
  @rolling_method_type "rolling_method"

  # All concept metadata keys read by the library at runtime. Keys not in
  # this set and not otherwise declared trigger a Logger.warning at load
  # time (see Loader.warn_unknown_metadata_keys/3). Kept as a plain list;
  # the MapSet is built at call time because embedding a compile-time
  # MapSet literal violates its opaque type under dialyzer.
  @structural_metadata_keys ~w(
    name type required_count available_when effect_target roll_reference roll
    filter choices level requires starting_equipment target_type dice bonus_field
    contributes hidden
  )

  @doc "Reserved type ID for character advancement (progression) concepts."
  def progression_type, do: @progression_type

  @doc "Reserved type ID for die-roll definition concepts."
  def roll_type, do: @roll_type

  @doc "Reserved type ID for rolling-method concepts."
  def rolling_method_type, do: @rolling_method_type

  @doc "The set of concept metadata keys the library reads at runtime."
  def structural_metadata_keys, do: MapSet.new(@structural_metadata_keys)

  @doc """
  The decision scope tuple for a choice made under a progression.

  ## Examples

      iex> ExTTRPGDev.RuleSystem.Vocabulary.progression_scope("asi_or_feat")
      {"character_progression", "asi_or_feat"}

  """
  def progression_scope(progression_id), do: {@progression_type, progression_id}

  @doc """
  The canonical choice ID for the nth (1-based) choice of a progression.

  ## Examples

      iex> ExTTRPGDev.RuleSystem.Vocabulary.progression_choice_id(2)
      "choice_2"

  """
  def progression_choice_id(n) when is_integer(n) and n >= 1, do: "choice_#{n}"
end
