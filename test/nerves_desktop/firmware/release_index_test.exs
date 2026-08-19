defmodule NervesDesktop.Firmware.ReleaseIndexTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Firmware.ReleaseIndex

  @device %{
    id: "network:nerves-3671.local",
    type: :network,
    product: "circuits_quickstart",
    platform: "rpi0_2",
    version: "0.16.2",
    uuid: "7e2ab1b1-1882-5841-7382-ad4ada05a00d"
  }

  describe "compare/2 — the rule the badge is drawn from" do
    test "matching uuids mean the device is current" do
      release = %{version: "0.16.2", uuid: @device.uuid, url: "u"}

      assert ReleaseIndex.compare(@device, release) == :current
    end

    test "a different uuid means an update is available, even at the same version" do
      release = %{version: "0.16.2", uuid: "0000-different", url: "u"}

      assert ReleaseIndex.compare(@device, release) == {:stale, "0.16.2"}
    end

    test "falls back to versions when the release uuid could not be read" do
      release = %{version: "0.17.0", uuid: nil, url: "u"}

      assert ReleaseIndex.compare(@device, release) == {:stale, "0.17.0"}
      assert ReleaseIndex.compare(@device, %{release | version: "0.16.2"}) == :current
    end

    test "falls back to versions when the device does not advertise a uuid" do
      device = %{@device | uuid: nil}
      release = %{version: "0.16.2", uuid: "abc", url: "u"}

      assert ReleaseIndex.compare(device, release) == :current
    end

    test "is unknown when neither side offers anything to compare" do
      device = %{@device | uuid: nil, version: nil}
      release = %{version: nil, uuid: nil, url: "u"}

      assert ReleaseIndex.compare(device, release) == :unknown
    end
  end

  describe "statuses/2" do
    setup do
      pid = start_supervised!({ReleaseIndex, name: :"idx_#{System.unique_integer([:positive])}"})
      %{index: pid}
    end

    test "reports pending until a release resolves", %{index: index} do
      assert ReleaseIndex.statuses(index, [@device]) == %{@device.id => :pending}
    end

    test "devices that match no catalog image are never pending", %{index: index} do
      device = %{@device | product: "my_custom_app", id: "network:custom"}

      assert ReleaseIndex.statuses(index, [device]) == %{device.id => :unknown}
    end

    test "serial devices are left alone", %{index: index} do
      device = %{@device | type: :uart, id: "uart:/dev/ttyUSB0"}

      assert ReleaseIndex.statuses(index, [device]) == %{device.id => :unknown}
    end

    test "reports the comparison once a release is cached", %{index: index} do
      ReleaseIndex.put(index, {"elixir-circuits/circuits_quickstart", "rpi0_2"}, %{
        version: "0.17.0",
        uuid: "newer-uuid",
        url: "u"
      })

      assert ReleaseIndex.statuses(index, [@device]) == %{@device.id => {:stale, "0.17.0"}}
    end

    test "a failed lookup reads as unknown rather than pending forever", %{index: index} do
      ReleaseIndex.put_failure(index, {"elixir-circuits/circuits_quickstart", "rpi0_2"})

      assert ReleaseIndex.statuses(index, [@device]) == %{@device.id => :unknown}
    end
  end
end
