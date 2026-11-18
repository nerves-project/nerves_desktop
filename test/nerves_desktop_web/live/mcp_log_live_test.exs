defmodule NervesDesktopWeb.McpLogLiveTest do
  use NervesDesktopWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup do
    dir = Application.fetch_env!(:nerves_desktop, NervesDesktop.MCP)[:log_dir]
    name = "mcp-log-live-#{System.unique_integer([:positive])}"
    log = Path.join(dir, name <> ".log")
    File.mkdir_p!(dir)
    on_exit(fn -> File.rm(log) end)

    %{target: "/dev/" <> name, log: log}
  end

  defp printed(data), do: %{data: Base.encode64(data)}

  test "says so when a device has no log", %{conn: conn, target: target} do
    {:ok, view, _html} = live(conn, ~p"/mcp/log?target=#{target}")

    assert has_element?(view, "#mcp-log-empty")
    assert has_element?(view, "#mcp-log-open-console")
    refute has_element?(view, "#mcp-log-live")
  end

  test "prints the log and follows what is added to it", context do
    %{conn: conn, target: target, log: log} = context
    File.write!(log, "iex(1)> ")

    {:ok, view, _html} = live(conn, ~p"/mcp/log?target=#{target}")
    assert_push_event view, "print", %{data: data}
    assert data == Base.encode64("iex(1)> ")
    assert has_element?(view, "#mcp-log-path")

    File.write!(log, "1 + 1\r\n", [:append])

    Phoenix.PubSub.broadcast(
      NervesDesktop.PubSub,
      NervesDesktop.MCP.log_topic(target),
      {:mcp_log, target}
    )

    assert_push_event view, "print", %{data: data}
    assert %{data: ^data} = printed("1 + 1\r\n")
  end

  test "starts again when the log was started over", %{conn: conn, target: target, log: log} do
    File.write!(log, "a long first session")

    {:ok, view, _html} = live(conn, ~p"/mcp/log?target=#{target}")
    assert_push_event view, "print", %{data: _first}

    File.write!(log, "fresh")

    Phoenix.PubSub.broadcast(
      NervesDesktop.PubSub,
      NervesDesktop.MCP.log_topic(target),
      {:mcp_log, target}
    )

    assert_push_event view, "clear", %{}
    assert_push_event view, "print", %{data: data}
    assert %{data: ^data} = printed("fresh")
  end
end
