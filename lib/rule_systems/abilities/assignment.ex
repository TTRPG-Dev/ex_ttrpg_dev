defmodule ExRPG.RuleSystems.Abilities.Assignment do
  alias ExRPG.RuleSystems.Abilities.Assignment
  alias ExRPG.Dice

  @moduledoc """
  This module handles the different ways of assigning ability scores
  """

  defstruct [:rolling_methods, :point_buy]

  defmodule PointBuy do
    @moduledoc """
    PointBuy specification for ability score assignment
    """
    defstruct [:points, :score_costs]

    defmodule ScoreCost do
      @moduledoc """
      Mapping of specific ability scores to cost for PointBuy ability assignment
      """
      defstruct [:score, :cost]
    end
  end

  defmodule RollingMethod do
    @moduledoc """
    Specificiation for different rolling methods for ability assignment
    """
    defstruct [:name, :dice, :special, :default]
  end

  @doc """
  Returns the default assignment method for the defined assignment methods

  ## Examples

      iex> Assignment.default_assignment()
  """
  def default_assignment(%Assignment{
        rolling_methods: [%Assignment.RollingMethod{} = first | _tail] = rolling_methods
      }) do
    Enum.find(rolling_methods, first, fn method -> method.default == true end)
  end

  @doc """
  Generates an ability score using the Assignment.RollingMethod

  ## Examples

      iex> %Assignment.RollingMethod{dice: "3d6"}
      [3, 4, 2]
  """
  def roll_via_method!(%Assignment.RollingMethod{} = method) do
    Dice.roll(method.dice)
    |> Assignment.apply_method_special!(method.special)
  end

  @doc """
  Applies a method special to the rolled values

  ## Examples

      iex> Assignment.apply_method_special!([4, 3, 2, 1], "drop_lowest")
      [2, 3, 4]

  """
  def apply_method_special!([head | _tail] = rolls, special) when is_integer(head) do
    case special do
      "drop_lowest" ->
        [_lowest | the_rest] = Enum.sort(rolls)
        the_rest

      nil ->
        rolls

      unhandled ->
        raise "Special '#{unhandled}' is not handled for rolling methods"
    end
  end
end
