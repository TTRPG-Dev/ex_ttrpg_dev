defmodule ExTTRPGDevTest.CLI.RuleSystems do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias ExTTRPGDev.CLI

  setup do
    optimus = CLI.build_optimus()
    halt_fn = fn _code -> nil end
    {:ok, optimus: optimus, halt_fn: halt_fn}
  end

  defp dispatch_show_concepts(optimus, halt_fn, concept_type) do
    capture_io(fn ->
      CLI.dispatch(
        ["systems", "show", "dnd_5e_srd", "--concept-type", concept_type],
        optimus,
        halt_fn
      )
    end)
  end

  describe "systems list" do
    setup %{optimus: optimus, halt_fn: halt_fn} do
      output = capture_io(fn -> CLI.dispatch(["systems", "list"], optimus, halt_fn) end)
      {:ok, output: output}
    end

    test "prints configured systems header", %{output: output} do
      assert output =~ "Configured Systems:"
    end

    test "prints each system slug", %{output: output} do
      assert output =~ "dnd_5e_srd"
    end
  end

  describe "systems show" do
    setup %{optimus: optimus, halt_fn: halt_fn} do
      output =
        capture_io(fn -> CLI.dispatch(["systems", "show", "dnd_5e_srd"], optimus, halt_fn) end)

      {:ok, output: output}
    end

    test "prints the system name and slug", %{output: output} do
      assert output =~ "Name:"
      assert output =~ "Slug: dnd_5e_srd"
    end

    test "prints version", %{output: output} do
      assert output =~ "Version:"
    end

    test "prints the concept types section", %{output: output} do
      assert output =~ "Concept Types:"
    end

    test "lists known concept type ids", %{output: output} do
      assert output =~ "attr"
      assert output =~ "skill"
    end
  end

  describe "systems show --concept-type" do
    test "attr lists attribute concepts", %{optimus: optimus, halt_fn: halt_fn} do
      output = dispatch_show_concepts(optimus, halt_fn, "attr")
      assert output =~ "strength"
      assert output =~ "dexterity"
      assert output =~ "constitution"
    end

    test "skill lists skill concepts", %{optimus: optimus, halt_fn: halt_fn} do
      output = dispatch_show_concepts(optimus, halt_fn, "skill")
      assert output =~ "acrobatics"
    end

    test "unknown type prints no-concepts message", %{optimus: optimus, halt_fn: halt_fn} do
      output = dispatch_show_concepts(optimus, halt_fn, "nonexistent_type")
      assert output =~ "No concepts found"
    end
  end
end
