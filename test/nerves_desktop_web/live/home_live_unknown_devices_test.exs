defmodule NervesDesktopWeb.HomeLiveUnknownDevicesTest do
  use NervesDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @nerves %{
    id: "network:nerves-1234.local",
    name: "nerves-1234",
    hostname: "nerves-1234.local",
    target: "nerves-1234.local",
    type: :network,
    tags: [:nerves]
  }

  @printer %{
    id: "network:printer.local",
    name: "printer",
    hostname: "printer.local",
    target: "printer.local",
    type: :network,
    tags: []
  }

  test "unknown devices stay hidden until asked for", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    send(view.pid, {:devices_updated, [@printer, @nerves]})

    assert has_element?(view, "#nerves-devices tr", "nerves-1234")
    refute has_element?(view, "#unknown-devices")
    assert has_element?(view, "#toggle-unknown-devices", "Show all (1 unknown device)")

    view |> element("#toggle-unknown-devices") |> render_click()
    assert has_element?(view, "#unknown-devices tr", "printer")

    view |> element("#toggle-unknown-devices") |> render_click()
    refute has_element?(view, "#unknown-devices")
  end

  test "offers unknown devices when no Nerves device answered", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    send(view.pid, {:devices_updated, [@printer]})

    refute has_element?(view, "#nerves-devices")

    view |> element("#toggle-unknown-devices") |> render_click()
    assert has_element?(view, "#unknown-devices tr", "printer")
  end

  test "has no toggle when every device looks like Nerves", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    send(view.pid, {:devices_updated, [@nerves]})

    assert has_element?(view, "#nerves-devices tr", "nerves-1234")
    refute has_element?(view, "#toggle-unknown-devices")
  end
end
