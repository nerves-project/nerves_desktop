defmodule NervesDesktop.DeviceScanner do
  use GenServer
  require Logger

  @topic "discovery"
  @scan_interval :timer.seconds(10)

  # Common USB-Serial Chip Mappings (FTDI, CP210x, CH34x)
  @chip_mappings %{
    0x0403 => "FTDI USB-Serial",
    0x10C4 => "CP210x USB-Serial",
    0x1A86 => "CH34x USB-Serial"
  }

  @vids Map.keys(@chip_mappings)

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
      network_devices = NervesDiscovery.discover() |> Enum.map(&normalize_network_device/1)
      uart_devices = Circuits.UART.enumerate() |> normalize_uart_devices()

      network_devices ++ uart_devices
    end)

    %{state | scanning: true, timer: nil}
  end

  defp normalize_network_device(device) do
    target =
      if device[:hostname] && device[:hostname] != "" do
        device.hostname
      else
        device.ip
      end

    Map.merge(device, %{
      id: "network:#{target}",
      target: target,
      type: :network,
      product: device[:product],
      version: device[:version],
      platform: device[:platform]
    })
  end

  defp normalize_uart_devices(enumerate_output) do
    enumerate_output
    |> Enum.filter(fn {_port, info} ->
      info[:vendor_id] in @vids
    end)
    |> Enum.map(fn {port, info} ->
      vendor_id = info[:vendor_id]
      manufacturer = info[:manufacturer] || ""

      chip_name = @chip_mappings[vendor_id] || "USB-Serial Device"

      # Use manufacturer if available, otherwise use our mapped chip name
      display_name = 
        cond do
          manufacturer != "" -> manufacturer
          true -> chip_name
        end

      %{
        id: "uart:#{port}",
        name: display_name,
        hostname: port,
        target: port,
        type: :uart,
        ip: nil,
        product: info[:description] || chip_name,
        version: nil,
        platform: nil,
        manufacturer: info[:manufacturer],
        vendor_id: info[:vendor_id],
        product_id: info[:product_id]
      }
    end)
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
