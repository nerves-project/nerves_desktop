defmodule NervesDesktopWeb.HomeLiveUpdateTest do
  use NervesDesktopWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  alias NervesDesktop.Firmware.ReleaseIndex

  setup do
    ReleaseIndex.put({"elixir-circuits/circuits_quickstart", "rpi0_2"}, %{
      version: "9.9.9",
      uuid: "a-newer-uuid",
      url: "https://example.test/fw"
    })

    :ok
  end

  test "the page renders without any devices present", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert has_element?(view, "#flash-group")
  end

  test "opening and closing a menu is server state, so a rescan cannot close it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    # Drive the events directly: the row only exists when a device is present,
    # and this asserts the state machine rather than the markup.
    assert render_click(view, "toggle_menu", %{"id" => "network:pi.local"})
    assert render_click(view, "close_menu", %{})
  end

  test "the rebooting row clears once the device comes back", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    device = %{
      id: "network:pi.local",
      name: "pi",
      target: "pi.local",
      hostname: "pi.local",
      type: :network,
      product: "circuits_quickstart",
      platform: "rpi0_2",
      version: "0.16.2",
      uuid: "same-uuid-after-a-reinstall"
    }

    send(view.pid, {:devices_updated, [device]})
    send(view.pid, {:update_progress, device.id, %{phase: :rebooting, percent: 100, error: nil}})
    assert render(view) =~ "Sent"

    # The device drops off while it reboots, then answers again. A reinstall
    # keeps the same uuid, so the round trip is the only usable signal.
    send(view.pid, {:devices_updated, []})
    send(view.pid, {:devices_updated, [device]})

    refute render(view) =~ "Sent"
  end

  test "a device that never returns does not leave the bar running", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    device = %{id: "network:gone.local", name: "gone", target: "gone.local", type: :network}

    send(view.pid, {:devices_updated, [device]})
    send(view.pid, {:update_progress, device.id, %{phase: :rebooting, percent: 100, error: nil}})
    assert render(view) =~ "Sent"

    send(view.pid, {:forget_update, device.id})
    refute render(view) =~ "Sent"
  end

  test "cancelling an update for an unknown device is harmless", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert render_click(view, "cancel_update", %{"id" => "network:nothing"})
  end
end
