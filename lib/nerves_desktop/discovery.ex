defmodule NervesDesktop.Discovery do
  use GenServer
  require Logger

  @topic "discovery"
  @scan_interval :timer.seconds(10)

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def scan_now do
    GenServer.cast(__MODULE__, :scan)
  end

  def get_devices do
    GenServer.call(__MODULE__, :get_devices)
  end

  @impl true
  def init(_opts) do
    schedule_scan(0)
    {:ok, %{devices: [], scanning: false}}
  end

  @impl true
  def handle_call(:get_devices, _from, state) do
    {:reply, state.devices, state}
  end

  @impl true
  def handle_cast(:scan, state) do
    if state.scanning do
      {:noreply, state}
    else
      {:noreply, start_scan(state)}
    end
  end

  @impl true
  def handle_info(:scan, state) do
    if state.scanning do
      schedule_scan()
      {:noreply, state}
    else
      {:noreply, start_scan(state)}
    end
  end

  @impl true
  def handle_info({ref, devices}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    broadcast_devices(devices)
    schedule_scan()
    {:noreply, %{state | devices: devices, scanning: false}}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Discovery scan failed: #{inspect(reason)}")
    schedule_scan()
    {:noreply, %{state | scanning: false}}
  end

  defp start_scan(state) do
    Task.Supervisor.async_nolink(NervesDesktop.TaskSupervisor, fn ->
      NervesDiscovery.discover()
    end)

    %{state | scanning: true}
  end

  defp schedule_scan(ms \\ @scan_interval) do
    Process.send_after(self(), :scan, ms)
  end

  defp broadcast_devices(devices) do
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, @topic, {:devices_updated, devices})
  end
end
