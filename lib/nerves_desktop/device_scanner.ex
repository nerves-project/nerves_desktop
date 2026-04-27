defmodule NervesDesktop.DeviceScanner do
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
    state = %{devices: [], scanning: false, timer: nil}
    {:ok, schedule_scan(state, 0)}
  end

  @impl true
  def handle_call(:get_devices, _from, state) do
    {:reply, state.devices, state}
  end

  @impl true
  def handle_cast(:scan, state) do
    {:noreply, perform_scan(state)}
  end

  @impl true
  def handle_info(:scan, state) do
    {:noreply, perform_scan(state)}
  end

  @impl true
  def handle_info({ref, devices}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    broadcast_devices(devices)

    state = %{state | devices: devices, scanning: false}
    {:noreply, schedule_scan(state)}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, reason}, state) do
    Logger.error("Discovery scan failed: #{inspect(reason)}")
    {:noreply, %{state | scanning: false} |> schedule_scan()}
  end

  defp perform_scan(state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    if state.scanning do
      # If already scanning, ensure a new one is scheduled after this one finishes
      %{state | timer: nil}
    else
      start_scan(state)
    end
  end

  defp start_scan(state) do
    Task.Supervisor.async_nolink(NervesDesktop.TaskSupervisor, fn ->
      NervesDiscovery.discover()
    end)

    %{state | scanning: true, timer: nil}
  end

  defp schedule_scan(state, ms \\ @scan_interval) do
    if state.timer, do: Process.cancel_timer(state.timer)
    timer = Process.send_after(self(), :scan, ms)
    %{state | timer: timer}
  end

  defp broadcast_devices(devices) do
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, @topic, {:devices_updated, devices})
  end
end
