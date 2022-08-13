defmodule ExRPG.Systems.Info do
  alias ExRPG.Systems
  alias ExRPG.Globals
  @moduledoc """
  Gets the general information for a configured system.
  """

  @doc """
  Returns the license for the given system if it has one.
  If the system doesn't exist, an exception is raised.

  ## Examples
  """
  def license!(system) when is_bitstring(system) do
    Path.join([Systems.system_path!(system), Globals.license_file_name])
    |> File.read!()
  end
end
