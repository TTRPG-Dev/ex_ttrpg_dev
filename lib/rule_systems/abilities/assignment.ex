defmodule ExRPG.RuleSystems.Abilities.Assignment do

  defstruct [:rolling_methods, :point_buy]

  defmodule PointBuy do
    defstruct [:points, :score_costs]

    defmodule ScoreCost do
      defstruct [:score, :cost]
    end
  end

  defmodule RollingMethod do
    defstruct [:name, :dice, :special]
  end
end
