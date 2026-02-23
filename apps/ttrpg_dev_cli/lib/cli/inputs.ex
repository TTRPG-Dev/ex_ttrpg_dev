defmodule ExTTRPGDev.CLI.Inputs do
  @moduledoc """
  Helpers for handling CLI input
  """

  @doc """
  Request user for a yes/no reponse.

  Returns `true` if user reponds with `y`, `Y`, `yes`, or `YES`. Othereide returns `false`.
  """
  def get_yes_no!(request) when is_bitstring(request) do
    case IO.gets("(y/n) #{request} ") do
      resp when is_bitstring(resp) ->
        resp
        |> String.trim()
        |> String.downcase()
        |> Kernel.then(fn lowered -> Enum.member?(["y", "yes"], lowered) end)

      {:error, error} ->
        raise(RuntimeError, error)

      :eof ->
        raise(RuntimeError, "Got `:eof` when getting user input")
    end
  end
end
