defmodule NervesDesktopWeb.HomeLiveTest do
  use NervesDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  test "renders the device list", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")
    assert has_element?(view, "#flash-group")
  end
end
