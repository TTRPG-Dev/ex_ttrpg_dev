defmodule ExTTRPGDev.RuleSystems.Abilities.Spec do
  alias ExTTRPGDev.RuleSystems.Abilities.Spec

  @moduledoc """
  A spec is the base definition of an ability, defining its name, abbreviation,
  and description. Additionally this module provides helper methods for
  individual specs and lists of specs.
  """

  defstruct [:name, :abbreviation, :description]

  @doc """
  Retunes the names of the given specs

  ## Examples

      iex> ExTTRPGDev.RuleSystems.Abilities.Spec.get_names(list_of_specs)
      ["names", "of", "specs]
  """
  def get_names([%Spec{} | _tail] = specs) do
    Enum.reduce(specs, [], fn spec, acc -> [spec.name | acc] end)
  end

  @doc """
  Returns the spec for the given spec name

  ## Examples

      iex> ExTTRPGDev.RuleSystems.Abilities.Spec.get_spec_by_name(list_of_specs, spec_name)
      %Spec{}
  """
  def get_spec_by_name([%Spec{} | _tail] = specs, spec_name) when is_bitstring(spec_name) do
    Enum.find(specs, fn %Spec{name: name} ->
      name == spec_name
    end)
  end
end
