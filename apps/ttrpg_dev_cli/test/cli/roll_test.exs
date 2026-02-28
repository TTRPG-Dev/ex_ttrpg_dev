defmodule ExTTRPGDevTest.CLI.Roll do
  use ExUnit.Case
  import ExUnit.CaptureIO

  alias ExTTRPGDev.CLI

  setup do
    optimus = CLI.build_optimus()
    halt_fn = fn _code -> nil end
    {:ok, optimus: optimus, halt_fn: halt_fn}
  end

  test "roll prints die spec as label in output", %{optimus: optimus, halt_fn: halt_fn} do
    output = capture_io(fn -> CLI.dispatch(["roll", "1d6"], optimus, halt_fn) end)
    assert output =~ "1d6"
  end

  test "roll prints a list of integer results", %{optimus: optimus, halt_fn: halt_fn} do
    output = capture_io(fn -> CLI.dispatch(["roll", "1d6"], optimus, halt_fn) end)
    assert output =~ ~r/\[\d+\]/
  end

  test "roll with multiple dice prints results for each spec", %{
    optimus: optimus,
    halt_fn: halt_fn
  } do
    output = capture_io(fn -> CLI.dispatch(["roll", "2d6,1d10"], optimus, halt_fn) end)
    assert output =~ "2d6"
    assert output =~ "1d10"
  end

  test "roll 3d6 prints a list of three results", %{optimus: optimus, halt_fn: halt_fn} do
    output = capture_io(fn -> CLI.dispatch(["roll", "3d6"], optimus, halt_fn) end)
    # Matches "3d6: [N, N, N]" with any integers
    assert output =~ ~r/3d6: \[\d+(, \d+){2}\]/
  end

  test "roll results are within the expected range", %{optimus: optimus, halt_fn: halt_fn} do
    output = capture_io(fn -> CLI.dispatch(["roll", "1d4"], optimus, halt_fn) end)
    # Extract the single integer from "[N]"
    [result_str] = Regex.run(~r/\[(\d+)\]/, output, capture: :all_but_first)
    result = String.to_integer(result_str)
    assert result >= 1 and result <= 4
  end
end
