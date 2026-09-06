defmodule NervesDesktopWeb.HomeLiveTest do
  use NervesDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the device list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#flash-group")
  end

  test "shows the dev-suffixed version in the sidebar", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/")
    assert html =~ "v#{NervesDesktop.version()}"
    assert html =~ "-dev"
  end
end
