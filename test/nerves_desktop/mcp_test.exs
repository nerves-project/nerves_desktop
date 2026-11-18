defmodule NervesDesktop.MCPTest do
  use ExUnit.Case, async: false

  alias NervesDesktop.MCP

  @moduletag :tmp_dir
  @moduletag capture_log: true

  @ports 23_700..23_709

  # Serial ports that do not exist: the server runs and just keeps retrying.
  defp device(name), do: %{type: :uart, target: "/dev/nerves-desktop-mcp-#{name}"}

  defp start_mcp(tmp_dir) do
    start_supervised!(
      {MCP,
       name: :mcp_under_test,
       path: Path.join(tmp_dir, "mcp.json"),
       ports: @ports,
       log_dir: Path.join(tmp_dir, "logs")}
    )
  end

  # Quitting the app takes the servers down with it.
  defp quit_app do
    stop_supervised!(MCP)
    Enum.each(["a", "b", "c"], &NervesMCP.stop_server(device(&1).target))
  end

  setup %{tmp_dir: tmp_dir} do
    on_exit(fn -> Enum.each(["a", "b", "c"], &NervesMCP.stop_server(device(&1).target)) end)
    {:ok, mcp: start_mcp(tmp_dir)}
  end

  test "each device gets its own port, counted up from the first", %{mcp: mcp} do
    assert {:ok, %{port: 23_700, url: "http://localhost:23700/mcp"}} =
             MCP.start_server(mcp, device("a"))

    assert {:ok, %{port: 23_701}} = MCP.start_server(mcp, device("b"))

    assert %{"/dev/nerves-desktop-mcp-a" => %{port: 23_700}, "/dev/nerves-desktop-mcp-b" => _} =
             MCP.servers(mcp)
  end

  test "starting a running server again changes nothing", %{mcp: mcp} do
    {:ok, server} = MCP.start_server(mcp, device("a"))

    assert MCP.start_server(mcp, device("a")) == {:ok, server}
  end

  test "a stopped server comes back on the port it had", %{mcp: mcp} do
    {:ok, _a} = MCP.start_server(mcp, device("a"))
    {:ok, %{port: port}} = MCP.start_server(mcp, device("b"))

    assert MCP.stop_server(mcp, device("b").target) == :ok
    refute Map.has_key?(MCP.servers(mcp), device("b").target)

    assert {:ok, %{port: ^port}} = MCP.start_server(mcp, device("b"))
  end

  test "a new device does not take the port of one that is switched off", %{mcp: mcp} do
    {:ok, %{port: port}} = MCP.start_server(mcp, device("a"))
    MCP.stop_server(mcp, device("a").target)

    assert {:ok, %{port: other}} = MCP.start_server(mcp, device("b"))
    assert other != port
    assert {:ok, %{port: ^port}} = MCP.start_server(mcp, device("a"))
  end

  test "reopening the app brings the same servers back on the same ports", %{tmp_dir: tmp_dir} do
    {:ok, a} = MCP.start_server(:mcp_under_test, device("a"))
    {:ok, b} = MCP.start_server(:mcp_under_test, device("b"))
    {:ok, _c} = MCP.start_server(:mcp_under_test, device("c"))
    MCP.stop_server(:mcp_under_test, device("c").target)

    quit_app()
    assert NervesMCP.server(device("a").target) == nil

    mcp = start_mcp(tmp_dir)

    assert MCP.servers(mcp) == %{device("a").target => a, device("b").target => b}
  end

  test "keeps a device's output in a file that outlives its server", context do
    %{mcp: mcp, tmp_dir: tmp_dir} = context
    target = device("a").target
    log = Path.join([tmp_dir, "logs", "nerves-desktop-mcp-a.log"])

    assert MCP.log_path(target, Path.join(tmp_dir, "logs")) == nil
    assert {:ok, %{log: ^log}} = MCP.start_server(mcp, device("a"))
    assert %{^target => %{log: ^log}} = MCP.servers(mcp)

    MCP.stop_server(mcp, target)
    assert MCP.log_path(target, Path.join(tmp_dir, "logs")) == log
  end

  test "tells whoever is watching that a log grew", %{tmp_dir: tmp_dir} do
    log = Path.join(tmp_dir, "watched.log")
    Phoenix.PubSub.subscribe(NervesDesktop.PubSub, MCP.log_topic("watched"))

    MCP.record("watched", log, "iex(1)> ")

    assert_receive {:mcp_log, "watched"}
    assert File.read!(log) == "iex(1)> "
  end

  test "starts a log over once it has grown large", %{mcp: mcp, tmp_dir: tmp_dir} do
    log = Path.join([tmp_dir, "logs", "nerves-desktop-mcp-a.log"])
    File.mkdir_p!(Path.dirname(log))
    File.write!(log, :binary.copy("x", 5_000_001))

    {:ok, _server} = MCP.start_server(mcp, device("a"))

    assert File.read!(log) == ""
  end

  test "broadcasts when the set of servers changes", %{mcp: mcp} do
    Phoenix.PubSub.subscribe(NervesDesktop.PubSub, MCP.topic())

    {:ok, server} = MCP.start_server(mcp, device("a"))
    assert_receive {:mcp_changed, %{"/dev/nerves-desktop-mcp-a" => ^server}}

    MCP.stop_server(mcp, device("a").target)
    assert_receive {:mcp_changed, servers} when servers == %{}
  end

  test "names a server after the device's hostname" do
    assert MCP.client_name(%{hostname: "nerves-4740.local", target: "nerves-4740.local"}) ==
             "nerves-4740"

    assert MCP.client_name(%{target: "192.168.1.10"}) == "192-168-1-10"

    assert MCP.client_name(%{hostname: "/dev/tty.usbserial-A1", type: :uart}) ==
             "tty-usbserial-A1"
  end

  test "builds the command that adds a server to an agent" do
    url = "http://localhost:13000/mcp"

    assert MCP.add_command(:claude_code, "nerves-4740", url) ==
             "claude mcp add --transport http nerves-4740 http://localhost:13000/mcp"

    assert MCP.add_command(:codex, "nerves-4740", url) ==
             "codex mcp add nerves-4740 --url http://localhost:13000/mcp"
  end

  test "a missing or damaged state file starts from nothing", %{tmp_dir: tmp_dir} do
    quit_app()
    File.write!(Path.join(tmp_dir, "mcp.json"), "not json")

    assert MCP.servers(start_mcp(tmp_dir)) == %{}
  end
end
