defmodule NervesDesktop.DeviceTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Device

  test "formats ipv4 addresses" do
    assert Device.format_address({192, 168, 1, 10}) == "192.168.1.10"
  end

  test "formats ipv6 addresses" do
    assert Device.format_address({0xFE80, 0, 0, 0, 0, 0, 0, 1}) == "fe80::1"
  end

  test "network devices always carry a name" do
    device = Device.from_network(%{hostname: "nerves.local", addresses: [{192, 168, 1, 10}]})
    assert device.name == "nerves.local"
    assert device.target == "nerves.local"
    assert device.ip == "192.168.1.10"
  end

  test "network devices fall back to an address when unnamed" do
    device = Device.from_network(%{addresses: [{192, 168, 1, 10}]})
    assert device.target == "192.168.1.10"
  end

  test "uart devices prefer the manufacturer over the mapped chip name" do
    [device] = Device.from_uart([{"/dev/ttyUSB0", %{vendor_id: 0x0403, manufacturer: "Acme"}}])
    assert device.name == "Acme"
  end

  test "uart devices fall back to the mapped chip name" do
    [device] = Device.from_uart([{"/dev/ttyUSB0", %{vendor_id: 0x0403, manufacturer: ""}}])
    assert device.name == "FTDI USB-Serial"
  end

  test "uart devices with unknown vendors are filtered out" do
    assert Device.from_uart([{"/dev/ttyUSB0", %{vendor_id: 0x9999}}]) == []
  end
end
