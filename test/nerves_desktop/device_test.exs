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

  test "network devices keep their tags from discovery" do
    printer = Device.from_network(%{hostname: "printer.local", addresses: [], tags: []})
    pi = Device.from_network(%{hostname: "nerves-1234.local", addresses: [], tags: [:nerves]})

    refute Device.nerves?(printer)
    assert Device.nerves?(pi)
  end

  test "devices without tags are not Nerves devices" do
    refute Device.nerves?(%{name: "printer"})
  end

  test "uart devices count as Nerves devices" do
    [device] = Device.from_uart([{"/dev/ttyUSB0", %{vendor_id: 0x0403}}])
    assert Device.nerves?(device)
  end

  test "nerves_first moves unknown devices last and keeps each group's order" do
    printer = %{name: "printer", tags: []}
    a = %{name: "nerves-a", tags: [:nerves]}
    b = %{name: "nerves-b", tags: [:nerves]}

    assert Device.nerves_first([printer, a, b]) == [a, b, printer]
  end
end
