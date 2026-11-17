defmodule NervesDesktopWeb.HomeLiveFoundTest do
  use NervesDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  @launch ~U[2026-11-12 10:00:00Z]

  defp device(name, first_seen_at, found_at_launch?) do
    %{
      id: "network:#{name}.local",
      name: name,
      hostname: "#{name}.local",
      target: "#{name}.local",
      type: :network,
      first_seen_at: first_seen_at,
      found_at_launch?: found_at_launch?
    }
  end

  test "marks only the most recent arrival as new", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    devices = [
      device("old-board", @launch, true),
      device("earlier-arrival", DateTime.add(@launch, 300, :second), false),
      device("latest-arrival", DateTime.add(@launch, 900, :second), false)
    ]

    send(view.pid, {:devices_updated, devices})

    assert has_element?(view, "tr[data-new-device]", "latest-arrival")
    refute has_element?(view, "tr[data-new-device]", "earlier-arrival")
    refute has_element?(view, "tr[data-new-device]", "old-board")
  end

  test "nothing is new when every device was there at launch", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/")

    send(view.pid, {:devices_updated, [device("old-board", @launch, true)]})

    assert has_element?(view, "time[datetime='#{DateTime.to_iso8601(@launch)}']")
    refute has_element?(view, "tr[data-new-device]")
  end
end
