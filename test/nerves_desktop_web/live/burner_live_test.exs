defmodule NervesDesktopWeb.BurnerLiveTest do
  use NervesDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias NervesDesktopWeb.BurnerLive

  # The template drives both the button's disabled state and its label from
  # this predicate, so pinning it here pins the rule that the write button
  # cannot be pressed while fwup is running.
  describe "writing?/1" do
    test "covers every status that means a write is in flight" do
      assert BurnerLive.writing?(:downloading)
      assert BurnerLive.writing?(:burning)
    end

    test "is false once the write has stopped" do
      refute BurnerLive.writing?(:idle)
      refute BurnerLive.writing?(:success)
      refute BurnerLive.writing?(:error)
    end
  end

  test "mounts without the Tauri shell", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/burner")

    assert has_element?(view, "button[phx-click='burn']")
  end

  test "the write button starts disabled with nothing chosen", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/burner")

    assert has_element?(view, "button[phx-click='burn'][disabled]")
  end

  test "the file picker is disabled without the shell that provides it", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/burner")

    assert has_element?(view, "button[phx-click='select_local_firmware'][disabled]")
  end
end
