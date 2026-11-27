defmodule NervesDesktop.Tray do
  @moduledoc """
  Keeps the tray menu's device list current for the Tauri shell to render.

  The menu is native, so the shell builds it. Everything it needs to know about
  a device is decided here: which list it belongs in, what it is called, where
  its console lives, what can be copied from it, and its MCP server. The menu is
  sent again whenever the devices or the running MCP servers change, and the
  shell sends back the MCP actions chosen from it.
  """

  use GenServer

  require Logger

  alias NervesDesktop.Device
  alias NervesDesktop.DeviceScanner
  alias NervesDesktop.MCP
  alias NervesDesktop.Native

  @topic "tray"
  @actions_topic "tray_action"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Replaces the devices the tray menu lists.
  """
  @spec update(GenServer.server(), [map()]) :: :ok
  def update(tray \\ __MODULE__, devices), do: GenServer.cast(tray, {:devices, devices})

  @doc """
  Encodes devices as the JSON the shell turns into menu items.
  """
  @spec payload([map()], %{binary() => map()}) :: binary()
  def payload(devices, servers \\ %{}) do
    {other, nerves} =
      devices
      |> Enum.sort_by(&String.downcase(label(&1)))
      |> Enum.split_with(&Device.unknown?/1)

    Jason.encode!(%{
      nerves: Enum.map(nerves, &entry(&1, servers)),
      other: Enum.map(other, &entry(&1, servers))
    })
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(NervesDesktop.PubSub, MCP.topic())
    Native.subscribe(@actions_topic)
    {:ok, %{devices: [], servers: %{}}, {:continue, :load}}
  end

  @impl true
  def handle_continue(:load, state) do
    {:noreply, render(%{state | devices: DeviceScanner.get_devices(), servers: MCP.servers()})}
  end

  @impl true
  def handle_cast({:devices, devices}, state), do: {:noreply, render(%{state | devices: devices})}

  @impl true
  def handle_info({:mcp_changed, servers}, state),
    do: {:noreply, render(%{state | servers: servers})}

  def handle_info("start_mcp:" <> id, state), do: {:noreply, act(state, id, &start_mcp/1)}

  def handle_info("stop_mcp:" <> id, state),
    do: {:noreply, act(state, id, &MCP.stop_server(&1.target))}

  def handle_info(message, state) do
    Logger.debug("Tray ignored #{inspect(message)}")
    {:noreply, state}
  end

  defp render(state) do
    Native.broadcast(@topic, payload(state.devices, state.servers))
    state
  end

  # Starting a server can take a while, and the menu should keep updating meanwhile.
  defp act(state, id, fun) do
    if device = Enum.find(state.devices, &(&1.id == id)) do
      Task.Supervisor.start_child(NervesDesktop.TaskSupervisor, fn -> fun.(device) end)
    end

    state
  end

  defp start_mcp(device) do
    with {:error, reason} <- MCP.start_server(device) do
      Logger.warning("Could not start the MCP server for #{device.target}: #{inspect(reason)}")
    end
  end

  defp entry(device, servers) do
    %{
      label: label(device),
      console: console_path(device),
      copy: copy_items(device),
      mcp: mcp_items(device, servers[device.target])
    }
  end

  defp label(%{type: :uart} = device), do: "#{device.name} (#{device.target})"
  defp label(device), do: device.name

  defp copy_items(%{type: :uart} = device), do: copy_item("Copy port", device.target)

  defp copy_items(device) do
    copy_item("Copy hostname", device[:hostname]) ++
      copy_item("Copy IP (#{device[:ip]})", device[:ip])
  end

  defp copy_item(label, value) when is_binary(value) and value != "",
    do: [%{label: label, value: value}]

  defp copy_item(_label, _value), do: []

  defp mcp_items(device, nil),
    do: [%{label: "Start MCP server", action: "start_mcp:#{device.id}"}]

  defp mcp_items(device, server) do
    [
      %{label: "MCP running on port #{server.port}", open: log_path(device)},
      %{label: "Stop MCP server", action: "stop_mcp:#{device.id}"}
    ]
  end

  defp console_path(device) do
    "/console?" <> URI.encode_query(target: device.target, name: device.name, connect: true)
  end

  defp log_path(device) do
    "/mcp/log?" <> URI.encode_query(target: device.target, name: device.name)
  end
end
