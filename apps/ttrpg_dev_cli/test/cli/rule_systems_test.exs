defmodule ExTTRPGDevTest.CLI.RuleSystems do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias ExTTRPGDev.CLI

  setup do
    optimus = CLI.build_optimus()
    halt_fn = fn _code -> nil end
    {:ok, optimus: optimus, halt_fn: halt_fn}
  end

  describe "systems list" do
    test "prints configured systems header", %{optimus: optimus, halt_fn: halt_fn} do
      output = capture_io(fn -> CLI.dispatch(["systems", "list"], optimus, halt_fn) end)
      assert output =~ "Configured Systems:"
    end

    test "prints each system slug", %{optimus: optimus, halt_fn: halt_fn} do
      output = capture_io(fn -> CLI.dispatch(["systems", "list"], optimus, halt_fn) end)
      assert output =~ "dnd_5e_srd"
    end
  end

  describe "systems show" do
    test "prints the system name and slug", %{optimus: optimus, halt_fn: halt_fn} do
      output =
        capture_io(fn -> CLI.dispatch(["systems", "show", "dnd_5e_srd"], optimus, halt_fn) end)

      assert output =~ "Name:"
      assert output =~ "Slug: dnd_5e_srd"
    end

    test "prints version", %{optimus: optimus, halt_fn: halt_fn} do
      output =
        capture_io(fn -> CLI.dispatch(["systems", "show", "dnd_5e_srd"], optimus, halt_fn) end)

      assert output =~ "Version:"
    end

    test "prints the concept types section", %{optimus: optimus, halt_fn: halt_fn} do
      output =
        capture_io(fn -> CLI.dispatch(["systems", "show", "dnd_5e_srd"], optimus, halt_fn) end)

      assert output =~ "Concept Types:"
    end

    test "lists known concept type ids", %{optimus: optimus, halt_fn: halt_fn} do
      output =
        capture_io(fn -> CLI.dispatch(["systems", "show", "dnd_5e_srd"], optimus, halt_fn) end)

      assert output =~ "attr"
      assert output =~ "skill"
    end

    test "--concept-type attr lists attribute concepts", %{optimus: optimus, halt_fn: halt_fn} do
      output =
        capture_io(fn ->
          CLI.dispatch(
            ["systems", "show", "dnd_5e_srd", "--concept-type", "attr"],
            optimus,
            halt_fn
          )
        end)

      assert output =~ "strength"
      assert output =~ "dexterity"
      assert output =~ "constitution"
    end

    test "--concept-type skill lists skill concepts", %{optimus: optimus, halt_fn: halt_fn} do
      output =
        capture_io(fn ->
          CLI.dispatch(
            ["systems", "show", "dnd_5e_srd", "--concept-type", "skill"],
            optimus,
            halt_fn
          )
        end)

      assert output =~ "acrobatics"
    end

    test "--concept-type with unknown type prints no-concepts message", %{
      optimus: optimus,
      halt_fn: halt_fn
    } do
      output =
        capture_io(fn ->
          CLI.dispatch(
            ["systems", "show", "dnd_5e_srd", "--concept-type", "nonexistent_type"],
            optimus,
            halt_fn
          )
        end)

      assert output =~ "No concepts found"
    end
  end
end
