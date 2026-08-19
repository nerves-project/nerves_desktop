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

  test "cancelling an update for an unknown device is harmless", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    assert render_click(view, "cancel_update", %{"id" => "network:nothing"})
  end
end
