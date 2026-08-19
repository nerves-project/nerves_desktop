defmodule NervesDesktop.Firmware.Upload.ProgressTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Firmware.Upload.Progress

  test "reads a percentage out of fwup's bar" do
    assert Progress.percent("  42% [=========           ]") == 42
  end

  test "takes the most recent value when a chunk carries several" do
    assert Progress.percent("10% [..]\n20% [....]\n30% [......]\n") == 30
  end

  test "tolerates a space before the sign" do
    assert Progress.percent("7 %") == 7
  end

  test "clamps nonsense rather than reporting a bar past full" do
    assert Progress.percent("999%") == 100
  end

  test "output with no percentage reports nothing, leaving the bar indeterminate" do
    assert Progress.percent("Erasing flash...\n") == nil
    assert Progress.percent("") == nil
  end

  test "report/2 invokes the callback only when there is something to report" do
    me = self()
    on_progress = &send(me, {:progress, &1})

    Progress.report("55% [====]", on_progress)
    assert_received {:progress, 55}

    Progress.report("Rebooting", on_progress)
    refute_received {:progress, _}
  end

  test "report/2 without a callback is harmless" do
    assert Progress.report("55%", nil) == :ok
  end
end
