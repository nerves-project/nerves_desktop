defmodule NervesDesktop.FirmwareTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Firmware

  describe "total_percent/3 when the image has to be fetched first" do
    test "downloading fills the first half" do
      assert Firmware.total_percent(:downloading, 0, true) == 0
      assert Firmware.total_percent(:downloading, 50, true) == 25
      assert Firmware.total_percent(:downloading, 100, true) == 50
    end

    test "writing picks up where downloading left off" do
      assert Firmware.total_percent(:uploading, 0, true) == 50
      assert Firmware.total_percent(:uploading, 50, true) == 75
      assert Firmware.total_percent(:uploading, 100, true) == 100
    end

    test "the bar never goes backwards between the two phases" do
      assert Firmware.total_percent(:downloading, 100, true) <=
               Firmware.total_percent(:uploading, 0, true)
    end
  end

  describe "total_percent/3 when the image is already on disk" do
    test "writing owns the whole bar" do
      assert Firmware.total_percent(:uploading, 0, false) == 0
      assert Firmware.total_percent(:uploading, 50, false) == 50
      assert Firmware.total_percent(:uploading, 100, false) == 100
    end
  end

  test "rebooting means the job is done either way" do
    assert Firmware.total_percent(:rebooting, 0, true) == 100
    assert Firmware.total_percent(:rebooting, 0, false) == 100
  end

  test "nonsense percentages are clamped rather than overflowing the bar" do
    assert Firmware.total_percent(:uploading, 140, false) == 100
    assert Firmware.total_percent(:uploading, -10, true) == 50
  end

  describe "phase_floor/2" do
    test "starts each phase where the previous one ended" do
      assert Firmware.phase_floor(:downloading, true) == 0
      assert Firmware.phase_floor(:uploading, true) == 50
      assert Firmware.phase_floor(:uploading, false) == 0
    end
  end
end
