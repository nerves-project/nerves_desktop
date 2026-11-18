defmodule NervesDesktopWeb.ConsoleLiveTest do
  use NervesDesktopWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  test "renders without a device selected", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console")

    assert has_element?(view, "#connection-form")
  end

  test "the password field starts empty for an unknown device", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/console?target=mystery.local&name=mystery")

    assert has_element?(view, "#connection-form input[type=password][value='']")
  end

  describe "a serial device with an MCP server" do
    @device %{
      id: "uart:/dev/nerves-desktop-console-test",
      name: "FTDI",
      hostname: "/dev/nerves-desktop-console-test",
      target: "/dev/nerves-desktop-console-test",
      type: :uart
    }

    setup %{conn: conn} do
      on_exit(fn ->
        NervesDesktop.MCP.stop_server(@device.target)

        case Registry.lookup(NervesDesktop.ConnectionRegistry, @device.target) do
          [{pid, _module}] -> NervesDesktop.ConnectionSupervisor.stop_child(pid)
          [] -> :ok
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/console")
      send(view.pid, {:devices_updated, [@device]})

      view
      |> element("#connection-form")
      |> render_change(%{"connection" => %{"target" => @device.target, "password" => ""}})

      %{view: view}
    end

    @tag capture_log: true
    test "opens the console through the server", %{view: view} do
      {:ok, _server} = NervesDesktop.MCP.start_server(@device)

      view |> element("#connection-form") |> render_submit()

      assert has_element?(view, "#console-mcp-note")
    end

    @tag capture_log: true
    test "cannot open a port that is not there without it", %{view: view} do
      view |> element("#connection-form") |> render_submit()

      refute has_element?(view, "#console-mcp-note")
    end
  end

  describe "prefilling a known image's password" do
    setup %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/console")

      device = %{
        name: "nerves-3671",
        hostname: "nerves-3671.local",
        target: "nerves-3671.local",
        type: :network,
        product: "circuits_quickstart",
        platform: "rpi0_2"
      }

      send(view.pid, {:devices_updated, [device]})
      %{view: view, device: device}
    end

    test "choosing the device fills in its documented password", %{view: view, device: device} do
      view
      |> element("#connection-form")
      |> render_change(%{"connection" => %{"target" => device.target, "password" => ""}})

      assert has_element?(view, "#connection-form input[type=password][value='circuits']")
    end

    test "does not overwrite a password typed for that device", %{view: view, device: device} do
      form = element(view, "#connection-form")

      render_change(form, %{"connection" => %{"target" => device.target, "password" => ""}})
      render_change(form, %{"connection" => %{"target" => device.target, "password" => "mine"}})

      assert has_element?(view, "#connection-form input[type=password][value='mine']")
    end

    test "switching to a device we know nothing about clears it", %{view: view, device: device} do
      form = element(view, "#connection-form")

      render_change(form, %{"connection" => %{"target" => device.target, "password" => ""}})

      render_change(form, %{
        "connection" => %{"target" => "other.local", "password" => "circuits"}
      })

      assert has_element?(view, "#connection-form input[type=password][value='']")
    end
  end
end
