defmodule ExTTRPGDev.Slug do
  @moduledoc false
  # What counts as a valid slug for the library's filesystem adapters, where
  # a slug becomes a file or directory name. Defined once so the character
  # and rule system stores agree on it.

  @pattern ~r/\A[A-Za-z0-9_\-]+\z/

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(slug), do: is_binary(slug) and Regex.match?(@pattern, slug)
end
