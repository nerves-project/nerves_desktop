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

  @tag capture_log: true
  test "a device's MCP server is started and stopped from its menu", %{conn: conn} do
    device = %{
      id: "uart:/dev/home-live-mcp",
      name: "Adapter",
      target: "/dev/home-live-mcp",
      type: :uart
    }

    on_exit(fn -> NervesDesktop.MCP.stop_server(device.target) end)

    {:ok, view, _html} = live(conn, ~p"/")
    send(view.pid, {:devices_updated, [device]})
    refute has_element?(view, ~s([id="mcp-#{device.id}"]))

    render_click(view, "toggle_menu", %{"id" => device.id})
    view |> element(~s([id="mcp-toggle-#{device.id}"])) |> render_click()
    assert has_element?(view, ~s([id="mcp-#{device.id}"]))
    assert has_element?(view, ~s([id="mcp-copy-url-#{device.id}"]))
    assert has_element?(view, ~s([id="mcp-log-#{device.id}"]))
    assert has_element?(view, ~s([id="mcp-copy-claude_code-#{device.id}"]))
    assert has_element?(view, ~s([id="mcp-copy-codex-#{device.id}"]))

    render_click(view, "toggle_menu", %{"id" => device.id})
    view |> element(~s([id="mcp-toggle-#{device.id}"])) |> render_click()
    refute has_element?(view, ~s([id="mcp-#{device.id}"]))
    refute has_element?(view, ~s([id="mcp-log-#{device.id}"]))

    render_click(view, "toggle_menu", %{"id" => device.id})
    assert has_element?(view, ~s([id="mcp-last-log-#{device.id}"]))
  end
end
