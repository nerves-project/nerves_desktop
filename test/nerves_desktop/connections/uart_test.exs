defmodule NervesDesktop.Connections.UARTTest do
  use ExUnit.Case, async: false

  alias NervesDesktop.Connection
  alias NervesDesktop.Connections.UART
  alias NervesDesktop.MCP

  @moduletag :tmp_dir
  @moduletag capture_log: true

  # A serial port that does not exist: it cannot be opened directly, while an
  # MCP server for it runs and keeps retrying.
  @target "/dev/nerves-desktop-uart-test"
  @device %{type: :uart, target: @target}

  setup %{tmp_dir: tmp_dir} do
    on_exit(fn -> NervesMCP.stop_server(@target) end)

    mcp =
      start_supervised!(
        {MCP, name: :uart_test_mcp, path: Path.join(tmp_dir, "mcp.json"), ports: 23_710..23_719}
      )

    Phoenix.PubSub.subscribe(NervesDesktop.PubSub, Connection.topic(@target))
    %{mcp: mcp, console: start_supervised!({UART, target: @target})}
  end

  defp worker_state, do: :sys.get_state(NervesMCP.Connection.whereis(@target))

  defp attached_again?(_console, 0), do: false

  defp attached_again?(console, tries) do
    with pid when is_pid(pid) <- NervesMCP.Connection.whereis(@target),
         %{console: {^console, _ref}} <- :sys.get_state(pid) do
      true
    else
      _not_yet -> retry_attached(console, tries)
    end
  catch
    :exit, _gone -> retry_attached(console, tries)
  end

  defp retry_attached(console, tries) do
    receive do
    after
      50 -> attached_again?(console, tries - 1)
    end
  end

  test "fails to connect when nothing holds the port", %{console: console} do
    assert {:error, _reason} = UART.connect(console, @target, "root", nil)
  end

  test "goes through the MCP server when one holds the port", %{mcp: mcp, console: console} do
    {:ok, _server} = MCP.start_server(mcp, @device)

    assert UART.connect(console, @target, "root", nil) == :ok
    assert {^console, _ref} = worker_state().console

    send(console, {:console_data, "iex(1)> "})
    assert_receive {:connection_output, @target, "iex(1)> "}
    assert UART.get_history(console) == "iex(1)> "
  end

  test "finds the server's connection again after it restarts", %{mcp: mcp, console: console} do
    {:ok, _server} = MCP.start_server(mcp, @device)
    :ok = UART.connect(console, @target, "root", nil)

    worker = NervesMCP.Connection.whereis(@target)
    ref = Process.monitor(worker)
    Process.exit(worker, :kill)
    assert_receive {:DOWN, ^ref, :process, ^worker, :killed}

    assert attached_again?(console, 50)
  end

  test "closes when the MCP server stops and the port cannot be opened", context do
    %{mcp: mcp, console: console} = context
    {:ok, _server} = MCP.start_server(mcp, @device)
    :ok = UART.connect(console, @target, "root", nil)
    ref = Process.monitor(console)

    MCP.stop_server(mcp, @target)

    assert_receive {:connection_closed, @target}
    assert_receive {:DOWN, ^ref, :process, ^console, :normal}
  end
end
