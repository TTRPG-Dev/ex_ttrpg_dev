defmodule ExTTRPGDev.RuleSystem.Versioning do
  @moduledoc """
  Version checks for rule system content.

  A rule system's `module.toml` carries two version-related keys (see
  `ExTTRPGDev.RuleSystem.RuleModule`): its own content `version`, and an
  optional `library_requirement`. A system declaring a `library_requirement`
  is *canonical*: content maintained alongside the library, eligible for
  automatic replacement by newer releases of itself. Every other system
  (user-authored or cloned) is exempt from replacement.

  Breaking-ness follows SemVer: before 1.0 the minor component is the
  breaking one, from 1.0 on the major is.

  Note that a two-part `~>` requirement does *not* pin a pre-1.0 minor:
  `"~> 0.15"` means `>= 0.15.0 and < 1.0.0`. Canonical content that should
  only run against 0.15.x releases must declare `"~> 0.15.0"`.
  """

  alias ExTTRPGDev.RuleSystem.RuleModule

  @doc """
  The running `ex_ttrpg_dev` library version, as a string.

  ## Examples
      iex> ExTTRPGDev.RuleSystem.Versioning.library_version() |> Version.parse() |> elem(0)
      :ok

  """
  @spec library_version() :: String.t()
  def library_version do
    :ex_ttrpg_dev |> Application.spec(:vsn) |> to_string()
  end

  @doc """
  Returns true if the rule module is canonical content, i.e. it declares a
  `library_requirement`.

  ## Examples
      iex> alias ExTTRPGDev.RuleSystem.RuleModule
      iex> ExTTRPGDev.RuleSystem.Versioning.canonical?(%RuleModule{version: "1.0.0", library_requirement: "~> 0.15.0"})
      true
      iex> ExTTRPGDev.RuleSystem.Versioning.canonical?(%RuleModule{version: "1.0.0"})
      false

  """
  @spec canonical?(RuleModule.t()) :: boolean()
  def canonical?(%RuleModule{library_requirement: requirement}), do: not is_nil(requirement)

  @doc """
  Returns true if `library_version` (default: the running library) satisfies
  the rule module's `library_requirement`.

  A module without a `library_requirement` places no constraint on the
  library, so it is always compatible.

  ## Examples
      iex> alias ExTTRPGDev.RuleSystem.RuleModule
      iex> mod = %RuleModule{version: "1.0.0", library_requirement: "~> 0.15.0"}
      iex> ExTTRPGDev.RuleSystem.Versioning.library_compatible?(mod, "0.15.3")
      true
      iex> ExTTRPGDev.RuleSystem.Versioning.library_compatible?(mod, "0.16.0")
      false
      iex> ExTTRPGDev.RuleSystem.Versioning.library_compatible?(%RuleModule{version: "x"}, "0.16.0")
      true

  """
  @spec library_compatible?(RuleModule.t(), String.t()) :: boolean()
  def library_compatible?(rule_module, library_version \\ library_version())

  def library_compatible?(%RuleModule{library_requirement: nil}, _library_version), do: true

  def library_compatible?(%RuleModule{library_requirement: requirement}, library_version) do
    Version.match?(library_version, requirement)
  end

  @doc """
  Returns true if moving from content version `from` to `to` crosses a
  breaking boundary: a change of major version, or of minor version while the
  major is 0.

  Both arguments must be valid SemVer strings.

  ## Examples
      iex> ExTTRPGDev.RuleSystem.Versioning.breaking_change?("1.2.0", "1.3.0")
      false
      iex> ExTTRPGDev.RuleSystem.Versioning.breaking_change?("1.2.0", "2.0.0")
      true
      iex> ExTTRPGDev.RuleSystem.Versioning.breaking_change?("0.2.0", "0.2.5")
      false
      iex> ExTTRPGDev.RuleSystem.Versioning.breaking_change?("0.2.0", "0.3.0")
      true

  """
  @spec breaking_change?(String.t(), String.t()) :: boolean()
  def breaking_change?(from, to) do
    breaking_component(Version.parse!(from)) != breaking_component(Version.parse!(to))
  end

  @doc """
  Returns true if content version `a` and `b` are on the same release line,
  i.e. moving between them is not a breaking change.

  Versions that aren't valid SemVer (allowed for non-canonical systems) are
  only on the same line as themselves.

  ## Examples
      iex> ExTTRPGDev.RuleSystem.Versioning.same_release_line?("1.2.0", "1.4.1")
      true
      iex> ExTTRPGDev.RuleSystem.Versioning.same_release_line?("1.2.0", "2.0.0")
      false
      iex> ExTTRPGDev.RuleSystem.Versioning.same_release_line?("first draft", "first draft")
      true

  """
  @spec same_release_line?(String.t(), String.t()) :: boolean()
  def same_release_line?(a, b) do
    with {:ok, _} <- Version.parse(a),
         {:ok, _} <- Version.parse(b) do
      not breaking_change?(a, b)
    else
      :error -> a == b
    end
  end

  defp breaking_component(%Version{major: 0, minor: minor}), do: {0, minor}
  defp breaking_component(%Version{major: major}), do: {major}
end
