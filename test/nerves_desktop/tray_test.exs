defmodule NervesDesktop.TrayTest do
  use ExUnit.Case, async: false

  alias NervesDesktop.Device
  alias NervesDesktop.MCP
  alias NervesDesktop.Tray

  defp payload(devices), do: devices_payload(devices, %{})
  defp devices_payload(devices, servers), do: devices |> Tray.payload(servers) |> Jason.decode!()

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

  test "serial adapters are listed with the Nerves devices and offer their port" do
    devices = Device.from_uart([{"/dev/ttyUSB0", %{vendor_id: 0x0403, manufacturer: "Acme"}}])

    assert %{"nerves" => [entry], "other" => []} = payload(devices)
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

  test "a device without an MCP server offers to start one" do
    device = Device.from_network(%{name: "nerves-1234", hostname: "nerves-1234.local"})

    assert %{"nerves" => [entry]} = payload([device])

    assert entry["mcp"] == [
             %{"label" => "Start MCP server", "action" => "start_mcp:#{device.id}"}
           ]
  end

  test "a running MCP server shows its status, which opens its log" do
    device = Device.from_network(%{name: "nerves-1234", hostname: "nerves-1234.local"})
    servers = %{device.target => %{port: 13_003}}

    assert %{"nerves" => [entry]} = devices_payload([device], servers)

    assert entry["mcp"] == [
             %{
               "label" => "MCP running on port 13003",
               "open" => "/mcp/log?target=nerves-1234.local&name=nerves-1234"
             },
             %{"label" => "Stop MCP server", "action" => "stop_mcp:#{device.id}"}
           ]
  end

  describe "actions chosen from the menu" do
    @moduletag capture_log: true

    # A serial port that does not exist: the server runs and just keeps retrying.
    @port "/dev/nerves-desktop-tray-test"

    setup do
      on_exit(fn -> MCP.stop_server(@port) end)

      [device] = Device.from_uart([{@port, %{vendor_id: 0x0403, manufacturer: "Acme"}}])
      tray = start_supervised!({Tray, name: :tray_under_test})
      Tray.update(tray, [device])
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, MCP.topic())

      %{tray: tray, device: device}
    end

    test "start and stop the device's MCP server", %{tray: tray, device: device} do
      send(tray, "start_mcp:#{device.id}")
      assert_receive {:mcp_changed, %{@port => _server}}, 15_000

      send(tray, "stop_mcp:#{device.id}")
      assert_receive {:mcp_changed, servers}, 15_000
      refute Map.has_key?(servers, @port)
    end

    test "an action for a device that has gone does nothing", %{tray: tray} do
      send(tray, "start_mcp:uart:/dev/gone")
      _ = :sys.get_state(tray)

      refute_receive {:mcp_changed, _}, 200
    end
  end
end
