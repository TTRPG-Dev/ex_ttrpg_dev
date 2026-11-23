defmodule ExTTRPGDev.RuleSystems.Bundled do
  @moduledoc """
  The rule systems shipped inside the library, under `priv/system_configs`.

  Bundled systems are a *source of releases*, not a place systems are loaded
  from: their content is installed into the configured
  `ExTTRPGDev.RuleSystem.Store` by `ExTTRPGDev.RuleSystems.sync_bundled/0`
  (or lazily, the first time an uninstalled bundled slug is loaded), and is
  loaded from the store like any other system from then on.
  """

  alias ExTTRPGDev.Globals
  alias ExTTRPGDev.RuleSystem.Source

  @doc """
  Lists the slugs of bundled systems.

  Returns `{:ok, [slug, ...]}`, or `{:error, reason}` if the bundled
  directory exists but can't be listed.

  ## Examples
      iex> {:ok, slugs} = ExTTRPGDev.RuleSystems.Bundled.list()
      iex> "dnd_5e_srd" in slugs
      true

  """
  @spec list() :: {:ok, [String.t()]} | {:error, term()}
  def list do
    base = Globals.system_configs_path()

    case File.ls(base) do
      {:ok, entries} ->
        {:ok,
         entries
         |> Enum.filter(&File.regular?(Path.join([base, &1, "module.toml"])))
         |> Enum.sort()}

      {:error, :enoent} ->
        {:ok, []}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Reads a bundled system's content."
  @spec fetch(String.t()) :: {:ok, Source.t()} | {:error, term()}
  def fetch(slug) do
    with {:ok, slugs} <- list() do
      if slug in slugs,
        do: Source.read(Path.join(Globals.system_configs_path(), slug)),
        else: {:error, :not_found}
    end
  end
end
