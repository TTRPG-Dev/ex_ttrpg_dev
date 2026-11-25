defmodule ExTTRPGDev.Slug do
  @moduledoc false
  # What counts as a valid slug for the library's filesystem adapters, where
  # a slug becomes a file or directory name. Defined once so the character
  # and rule system stores agree on it.
  #
  # A valid slug is:
  #
  # - Letters, combining marks and digits in any script, plus `_` and `-`.
  #   That excludes path separators, `.` (so no `..` or hidden files),
  #   whitespace and control characters. Combining marks are needed by
  #   scripts (e.g. Devanagari) that use them even when composed.
  # - In Unicode NFC form. Some filesystems (macOS) store names decomposed;
  #   requiring one form means two slugs that look alike are always the
  #   same string, so they can't silently name the same file or miss each
  #   other.
  # - At most `max_bytes/0` bytes of UTF-8. Filesystems cap a name at 255
  #   bytes, not characters; the margin leaves room for the `.json`
  #   extension and temporary-file affixes.
  #
  # Windows reserved device names (`con`, `nul`, ...) aren't rejected: that
  # would make a character named "Con" impossible on every platform to guard
  # an edge case on one.

  @pattern ~r/\A[\p{L}\p{M}\p{N}_\-]+\z/u
  @max_bytes 200

  @doc false
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc false
  @spec valid?(term()) :: boolean()
  def valid?(slug) when is_binary(slug) do
    byte_size(slug) <= @max_bytes and String.valid?(slug) and
      Regex.match?(@pattern, slug) and String.normalize(slug, :nfc) == slug
  end

  def valid?(_slug), do: false
end
