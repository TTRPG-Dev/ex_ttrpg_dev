defmodule ExTTRPGDev.CLI.Server.Handlers.Dice do
  @moduledoc """
  Handles the `roll` command: free-form dice rolling.
  """

  alias DiceLib.Basic, as: Dice

  def handle(%{"command" => "roll", "dice" => dice_str}, state) do
    specs =
      dice_str
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    results =
      specs
      |> Dice.multi_roll!()
      |> Enum.map(fn {spec, rolls} ->
        %{spec: spec, rolls: rolls, total: Enum.sum(rolls)}
      end)

    {:ok, %{results: results}, state}
  end

  def handle(%{"command" => cmd}, _state),
    do: {:error, "invalid arguments for command: #{inspect(cmd)}"}
end
