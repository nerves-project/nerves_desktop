defmodule NervesDesktop.TrayTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Device
  alias NervesDesktop.Tray

  defp payload(devices), do: devices |> Tray.payload() |> Jason.decode!()

  test "splits Nerves devices from everything else" do
    devices = [
      Device.from_network(%{name: "nas", hostname: "nas.local", addresses: [{192, 168, 1, 5}]}),
      Device.from_network(%{
        name: "nerves-1234",
        hostname: "nerves-1234.local",
        addresses: [{192, 168, 1, 10}]
      })
    ]

    assert %{"nerves" => [%{"label" => "nerves-1234"}], "other" => [%{"label" => "nas"}]} =
             payload(devices)
  end

  test "a device advertising firmware details is a Nerves device whatever its name" do
    device =
      Device.from_network(%{
        name: "kiosk",
        hostname: "kiosk.local",
        addresses: [{10, 0, 0, 2}],
        product: "kiosk_fw"
      })

    assert %{"nerves" => [%{"label" => "kiosk"}], "other" => []} = payload([device])
  end

  test "network devices offer their console, hostname and address" do
    device =
      Device.from_network(%{
        name: "nerves-1234",
        hostname: "nerves-1234.local",
        addresses: [{0xFE80, 0, 0, 0, 0, 0, 0, 1}, {192, 168, 1, 10}]
      })

    assert %{"nerves" => [entry]} = payload([device])
    assert entry["console"] == "/console?target=nerves-1234.local&name=nerves-1234&connect=true"

    assert entry["copy"] == [
             %{"label" => "Copy hostname", "value" => "nerves-1234.local"},
             %{"label" => "Copy IP (192.168.1.10)", "value" => "192.168.1.10"}
           ]
  end

  test "serial adapters are listed with the other devices and offer their port" do
    devices = Device.from_uart([{"/dev/ttyUSB0", %{vendor_id: 0x0403, manufacturer: "Acme"}}])

    assert %{"nerves" => [], "other" => [entry]} = payload(devices)
    assert entry["label"] == "Acme (/dev/ttyUSB0)"
    assert entry["console"] == "/console?target=%2Fdev%2FttyUSB0&name=Acme&connect=true"
    assert entry["copy"] == [%{"label" => "Copy port", "value" => "/dev/ttyUSB0"}]
  end

  test "devices are listed alphabetically" do
    devices =
      for name <- ["nerves-b", "Nerves-a"] do
        Device.from_network(%{name: name, hostname: "#{name}.local", addresses: [{10, 0, 0, 1}]})
      end

    assert %{"nerves" => [%{"label" => "Nerves-a"}, %{"label" => "nerves-b"}]} = payload(devices)
  end
end
