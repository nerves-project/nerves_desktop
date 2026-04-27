defmodule NervesDesktop.FelScanner do
  use GenServer
  require Logger

  @topic "fel_discovery"
  @scan_interval 5000

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def get_devices do
    GenServer.call(__MODULE__, :get_devices)
  end

  def scan_now do
    GenServer.cast(__MODULE__, :scan)
  end

  @impl true
  def init(_opts) do
    state = %{devices: [], timer: nil}
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

  defp perform_scan(state) do
    # Cancel existing timer if any
    if state.timer, do: Process.cancel_timer(state.timer)

    new_devices =
      case Sunxi.FEL.list_devices() do
        devices when is_list(devices) -> devices
        _ -> []
      end

    # Always broadcast so the UI can update the "Last Scan" timestamp
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, @topic, {:fel_devices_updated, new_devices})

    state
    |> Map.put(:devices, new_devices)
    |> schedule_scan()
  end

  defp schedule_scan(state, ms \\ @scan_interval) do
    timer = Process.send_after(self(), :scan, ms)
    %{state | timer: timer}
  end
end
