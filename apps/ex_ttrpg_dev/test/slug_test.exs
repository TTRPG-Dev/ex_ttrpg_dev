defmodule ExTTRPGDev.SlugTest do
  use ExUnit.Case, async: true

  alias ExTTRPGDev.Slug

  test "accepts letters and digits in any script, with _ and -" do
    for slug <- ~w(dnd_5e_srd my-homebrew zoë éowyn 日本 नमस्ते Δ1) do
      assert Slug.valid?(slug), "expected #{inspect(slug)} to be valid"
    end
  end

  test "rejects anything that could escape a directory or hide a file" do
    for slug <- ["", ".", "..", "../x", "a/b", "a\\b", ".hidden", "a.json", "a b", "tab\tname"] do
      refute Slug.valid?(slug), "expected #{inspect(slug)} to be invalid"
    end
  end

  test "rejects non-NFC forms" do
    decomposed = "zoë"
    refute Slug.valid?(decomposed)
    assert Slug.valid?(String.normalize(decomposed, :nfc))
  end

  test "caps length in bytes, not characters" do
    assert Slug.valid?(String.duplicate("a", Slug.max_bytes()))
    refute Slug.valid?(String.duplicate("a", Slug.max_bytes() + 1))
    # "ë" is two bytes in UTF-8.
    refute Slug.valid?(String.duplicate("ë", div(Slug.max_bytes(), 2) + 1))
  end

  test "rejects non-strings and invalid UTF-8" do
    refute Slug.valid?(nil)
    refute Slug.valid?(:atom)
    refute Slug.valid?(<<0xFF, 0xFE>>)
  end
end
