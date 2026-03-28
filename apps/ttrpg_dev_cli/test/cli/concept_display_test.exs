defmodule ExTTRPGDev.CLI.ConceptDisplayTest do
  use ExUnit.Case, async: true

  alias ExTTRPGDev.CLI.ConceptDisplay

  @spell %{
    "name" => "Fire Bolt",
    "level" => 1,
    "school" => "evocation",
    "verbal" => true,
    "somatic" => true,
    "material" => false,
    "casting_time" => "1 action"
  }

  @template "{{name}}: Level {{level}}, {{school}} ({{?verbal:V}}{{?somatic:S}}{{?material:M}})"

  describe "succinct mode" do
    test "returns name regardless of template" do
      assert ConceptDisplay.render(@template, @spell, :succinct) == "Fire Bolt"
    end

    test "returns name when no template" do
      assert ConceptDisplay.render(nil, @spell, :succinct) == "Fire Bolt"
    end

    test "returns empty string when name is absent" do
      assert ConceptDisplay.render(nil, %{}, :succinct) == ""
    end
  end

  describe "default mode with no template" do
    test "falls back to name" do
      assert ConceptDisplay.render(nil, @spell, :default) == "Fire Bolt"
    end
  end

  describe "default mode with template" do
    test "substitutes fields" do
      assert ConceptDisplay.render(@template, @spell, :default) ==
               "Fire Bolt: Level 1, evocation (VS)"
    end

    test "omits conditional text when field is false" do
      spell = Map.put(@spell, "verbal", false)
      result = ConceptDisplay.render(@template, spell, :default)
      assert result == "Fire Bolt: Level 1, evocation (S)"
    end

    test "omits conditional text when field is nil" do
      spell = Map.delete(@spell, "verbal")
      result = ConceptDisplay.render(@template, spell, :default)
      assert result == "Fire Bolt: Level 1, evocation (S)"
    end

    test "all components present" do
      spell = Map.put(@spell, "material", true)
      result = ConceptDisplay.render(@template, spell, :default)
      assert result == "Fire Bolt: Level 1, evocation (VSM)"
    end

    test "no components present" do
      spell = @spell |> Map.put("verbal", false) |> Map.put("somatic", false)
      result = ConceptDisplay.render(@template, spell, :default)
      assert result == "Fire Bolt: Level 1, evocation ()"
    end

    test "missing substitution field renders as empty string" do
      result = ConceptDisplay.render("{{name}} ({{missing}})", @spell, :default)
      assert result == "Fire Bolt ()"
    end
  end

  describe "verbose mode" do
    test "includes name and all non-hidden fields" do
      result = ConceptDisplay.render(nil, @spell, :verbose)
      assert String.starts_with?(result, "Fire Bolt")
      assert result =~ "level: 1"
      assert result =~ "school: evocation"
      assert result =~ "verbal: true"
    end

    test "excludes hidden field" do
      spell = Map.put(@spell, "hidden", true)
      result = ConceptDisplay.render(nil, spell, :verbose)
      refute result =~ "hidden:"
    end

    test "excludes name from details" do
      result = ConceptDisplay.render(nil, @spell, :verbose)
      refute result =~ "name: Fire Bolt"
    end

    test "verbose ignores template" do
      result = ConceptDisplay.render(@template, @spell, :verbose)
      assert result =~ "school: evocation"
    end
  end
end
