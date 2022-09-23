defmodule ExTTRPGDev.RuleSystems.Metadata do
  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.RuleSystems

  @moduledoc """
  Gets the general information for a configured system.
  """

  defstruct [:name, :short, :slug, :family, :series, :publisher]

  @doc """
  Returns the license for the given system if it has one.
  If the system doesn't exist, an exception is raised.

  ## Examples
  """
  def license!(system) when is_bitstring(system) do
    Path.join([RuleSystems.system_path!(system), Globals.license_file_name()])
    |> File.read!()
  end
end
