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

  @impl true
  def init(_opts) do
    schedule_scan(0)
    {:ok, %{devices: []}}
  end

  @impl true
  def handle_call(:get_devices, _from, state) do
    {:reply, state.devices, state}
  end

  @impl true
  def handle_info(:scan, state) do
    new_devices = 
      case Sunxi.FEL.list_devices() do
        devices when is_list(devices) -> devices
        _ -> []
      end

    # Always broadcast so the UI can update the "Last Scan" timestamp
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, @topic, {:fel_devices_updated, new_devices})

    schedule_scan()
    {:noreply, %{state | devices: new_devices}}
  end

  defp schedule_scan(ms \\ @scan_interval) do
    Process.send_after(self(), :scan, ms)
  end
end
