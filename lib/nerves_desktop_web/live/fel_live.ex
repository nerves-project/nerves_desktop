defmodule NervesDesktopWeb.FelLive do
  use NervesDesktopWeb, :live_view
  require Logger

  alias NervesDesktop.FelScanner
  alias NervesDesktop.FelLoader

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "fel_discovery")
    end

    {:ok,
     socket
     |> assign(devices: FelScanner.get_devices())
     |> assign(status: :idle)
     |> assign(message: "")
     |> assign(progress: 0)
     |> assign(last_scan_at: DateTime.utc_now())
     |> assign(scans_to_ignore: 0)}
  end

  @impl true
  def handle_info({:fel_devices_updated, devices}, socket) do
    if socket.assigns.scans_to_ignore > 0 do
      Logger.debug("[FEL] Ignoring scan update (count: #{socket.assigns.scans_to_ignore})")
      {:noreply, 
       socket 
       |> assign(scans_to_ignore: socket.assigns.scans_to_ignore - 1)
       |> assign(last_scan_at: DateTime.utc_now())}
    else
      {:noreply, assign(socket, devices: devices, last_scan_at: DateTime.utc_now())}
    end
  end

  @impl true
  def handle_info({:fel_progress, %{percentage: p, speed: s}}, socket) do
    {:noreply, assign(socket, progress: p, message: "Flashing... #{Float.round(s, 1)} kB/s")}
  end

  @impl true
  def handle_info({:flash_result, result}, socket) do
    case result do
      :ok ->
        {:noreply, assign(socket, status: :success, message: "USB FEL Loader flashed successfully!", progress: 100)}
      {:error, reason} ->
        {:noreply, assign(socket, status: :error, message: "Flash failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:update_status, status, message}, socket) do
    progress = case status do
      :downloading -> 15
      :flashing -> 40
      _ -> 0
    end
    {:noreply, assign(socket, status: status, message: message, progress: progress)}
  end

  @impl true
  def handle_event("scan_now", _params, socket) do
    FelScanner.scan_now()
    {:noreply, socket}
  end

  @impl true
  def handle_event("flash_loader", %{"sid" => sid}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1.sid == sid))
    board = detect_board(device.model)

    if is_nil(device) or is_nil(board) do
      {:noreply, put_flash(socket, :error, "Target device or board type not supported.")}
    else
      parent = self()
      Task.start_link(fn ->
        try do
          send(parent, {:update_status, :downloading, "Fetching latest release info..."})
          {:ok, version} = FelLoader.get_latest_version()
          
          send(parent, {:update_status, :downloading, "Downloading #{board}.bin..."})
          {:ok, bin_path} = FelLoader.download_loader(board, version)
          
          send(parent, {:update_status, :flashing, "Initializing flash..."})
          
          result = Sunxi.FEL.execute_uboot(bin_path, 
            device: device,
            on_progress: fn prog -> send(parent, {:fel_progress, prog}) end
          )
          
          send(parent, {:flash_result, result})
        rescue
          e -> send(parent, {:flash_result, {:error, e}})
        end
      end)

      {:noreply, 
       socket 
       |> assign(status: :started, message: "Starting process...", progress: 5)
       |> assign(scans_to_ignore: 3)}
    end
  end

  defp detect_board(model) do
    case model do
      "R528" -> "trellis"
      "T113" -> "trellis"
      "A64" -> "pine64"
      _ -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:fel}>
      <div class="p-4 md:p-8 w-full flex flex-col">
        <UI.page_header
          icon="hero-bolt"
          title="Allwinner FEL"
          subtitle="Interact with Allwinner devices via USB FEL mode"
        >
          <:actions>
            <UI.scanning_status
              last_scan_at={@last_scan_at}
              on_refresh="scan_now"
              id="last-scan-time-fel"
              class="w-full md:w-auto"
            />
          </:actions>
        </UI.page_header>

        <%= if Enum.empty?(@devices) do %>
          <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 items-stretch">
            <div class="bg-white rounded-[2.5rem] p-12 flex flex-col items-center justify-center text-center shadow-xl shadow-gray-200/50 border border-gray-100">
              <div class="w-24 h-24 bg-gray-50 rounded-full flex items-center justify-center mb-6 relative">
                <.icon name="hero-magnifying-glass" class="w-12 h-12 text-gray-300" />
              </div>
              <h3 class="text-2xl font-bold text-gray-900">No devices in FEL mode</h3>
              <p class="text-gray-500 mt-3 max-w-md leading-relaxed">
                Connect your Allwinner device via USB and put it into FEL mode.
              </p>

              <div class="mt-10 w-full grid grid-cols-1 md:grid-cols-2 gap-4">
                <div class="bg-gray-50 p-6 rounded-2xl border border-gray-100 text-left">
                  <h4 class="font-bold text-gray-900 text-sm mb-2 flex items-center gap-2">
                    <.icon name="hero-cpu-chip" class="w-4 h-4 text-primary" /> Trellis
                  </h4>
                  <p class="text-xs text-gray-500 leading-normal">Hold the <strong>FEL</strong> button while plugging in the USB-C cable.</p>
                </div>
                <div class="bg-gray-50 p-6 rounded-2xl border border-gray-100 text-left">
                  <h4 class="font-bold text-gray-900 text-sm mb-2 flex items-center gap-2">
                    <.icon name="hero-cpu-chip" class="w-4 h-4 text-primary" /> Pine64+
                  </h4>
                  <p class="text-xs text-gray-500 leading-normal">Check board documentation for the FEL pin or jumper location.</p>
                </div>
              </div>
            </div>

            <div class="bg-blue-50/50 p-10 rounded-[2.5rem] border border-blue-100 shadow-xl shadow-blue-900/5 flex flex-col">
              <h3 class="text-2xl font-bold text-blue-900 mb-6 flex items-center gap-3">
                <div class="p-2 bg-blue-100 rounded-lg">
                  <.icon name="hero-information-circle" class="w-6 h-6 text-blue-600" />
                </div>
                FEL Mode Info
              </h3>
              <div class="space-y-4 text-sm text-blue-800/80 leading-relaxed font-medium">
                <p>
                  FEL is a low-level subroutine in the Boot ROM of Allwinner SoCs. It's used for initial programming and recovery via USB.
                </p>
                <p>
                  The <strong>USB FEL Loader</strong> is a minimal U-Boot image that provides <strong>USB Mass Storage (UMS)</strong> support. Once flashed, the device will appear as a USB drive on your computer, allowing you to flash Nerves firmware directly to the internal storage or SD card.
                </p>
              </div>
            </div>
          </div>
        <% else %>
          <div class="flex flex-col gap-8">
            <div class="bg-white rounded-[2.5rem] shadow-xl shadow-gray-200/50 border border-gray-100 overflow-hidden w-full">
              <div class="overflow-x-auto">
                <table class="w-full text-left border-collapse">
                  <thead>
                    <tr class="bg-gray-50/50 border-b border-gray-100">
                      <th class="px-8 py-5 text-xs uppercase tracking-widest font-bold text-gray-400">Device Model</th>
                      <th class="px-8 py-5 text-xs uppercase tracking-widest font-bold text-gray-400">Location</th>
                      <th class="px-8 py-5 text-xs uppercase tracking-widest font-bold text-gray-400">Unique ID (SID)</th>
                      <th class="px-8 py-5 text-xs uppercase tracking-widest font-bold text-gray-400 text-right">Actions</th>
                    </tr>
                  </thead>
                  <tbody class="divide-y divide-gray-50">
                    <%= for device <- @devices do %>
                      <tr class="hover:bg-primary/[0.02] transition-colors group">
                        <td class="px-8 py-6">
                          <div class="flex items-center gap-4">
                            <div class="w-10 h-10 bg-gray-50 rounded-xl flex items-center justify-center border border-gray-100 group-hover:bg-white group-hover:shadow-sm transition-all">
                              <.icon name="hero-cpu-chip" class="w-5 h-5 text-gray-400 group-hover:text-primary" />
                            </div>
                            <div>
                              <div class="font-bold text-gray-900 text-lg">{device.model}</div>
                              <div :if={detect_board(device.model)} class="text-xs text-primary font-bold uppercase tracking-wider">
                                {detect_board(device.model)} detected
                              </div>
                            </div>
                          </div>
                        </td>
                        <td class="px-8 py-6">
                          <div class="text-sm font-mono text-gray-600 bg-gray-50 px-3 py-1 rounded-lg border border-gray-100 w-fit">
                            Bus {device.bus} : Dev {device.device}
                          </div>
                        </td>
                        <td class="px-8 py-6">
                          <div class="text-xs font-mono text-gray-400 break-all max-w-[200px] leading-tight">
                            {device.sid}
                          </div>
                        </td>
                        <td class="px-8 py-6 text-right">
                          <button
                            phx-click="flash_loader"
                            phx-value-sid={device.sid}
                            disabled={!detect_board(device.model) or @status in [:started, :downloading, :flashing]}
                            class="btn btn-primary btn-sm rounded-xl shadow-lg shadow-primary/20 flex items-center gap-2 w-fit ml-auto transition-all hover:scale-[1.02] active:scale-[0.98]"
                          >
                            <%= if @status in [:started, :downloading, :flashing] do %>
                              <span class="loading loading-spinner size-3"></span> Processing...
                            <% else %>
                              <.icon name="hero-fire" class="w-4 h-4" /> Flash USB FEL Loader
                            <% end %>
                          </button>
                        </td>
                      </tr>
                    <% end %>
                  </tbody>
                </table>
              </div>
            </div>

            <%= if @status != :idle do %>
              <div class="bg-gray-900 rounded-[2.5rem] p-10 text-white shadow-2xl overflow-hidden relative">
                <div class="absolute -top-10 -right-10 opacity-10">
                  <.icon name="hero-fire" class="w-64 h-64" />
                </div>
                
                <div class="relative z-10">
                  <div class="flex justify-between items-end mb-4">
                    <div>
                      <h3 class="text-2xl font-bold mb-1">Processing Device</h3>
                      <p class="text-gray-400 text-sm font-medium">{@message}</p>
                    </div>
                    <div class="text-right">
                      <div class="text-3xl font-black text-primary">{@progress}%</div>
                    </div>
                  </div>
                  
                  <div class="w-full bg-white/10 rounded-full h-4 overflow-hidden border border-white/5 shadow-inner">
                    <div
                      class="bg-primary h-full transition-all duration-500 rounded-full shadow-[0_0_20px_rgba(51,100,126,0.5)]"
                      style={"width: #{@progress}%"}
                    ></div>
                  </div>

                  <%= if @status == :success do %>
                    <div class="mt-8 space-y-4">
                      <div class="p-4 bg-green-500/20 text-green-300 rounded-2xl border border-green-500/30 flex items-center gap-3">
                        <.icon name="hero-check-circle" class="w-6 h-6" />
                        <div class="text-sm font-bold">Success! The device is now in UMS mode.</div>
                      </div>
                      
                      <div class="p-6 bg-amber-500/10 border border-amber-500/30 rounded-2xl space-y-2">
                        <div class="flex items-center gap-2 text-amber-400 font-black uppercase text-[10px] tracking-widest">
                          <.icon name="hero-exclamation-triangle" class="w-4 h-4" />
                          Important: System Dialog
                        </div>
                        <p class="text-xs text-amber-200/80 leading-relaxed">
                          If your computer shows a dialog saying <strong>"The disk you attached was not readable"</strong>, you MUST click <strong>Ignore</strong>. Do not click Eject, or the device will be disconnected.
                        </p>
                      </div>
                    </div>
                  <% end %>

                  <%= if @status == :error do %>
                    <div class="mt-8 p-4 bg-red-500/20 text-red-300 rounded-2xl border border-red-500/30 flex items-center gap-3">
                      <.icon name="hero-exclamation-triangle" class="w-6 h-6" />
                      <div class="text-sm font-bold">{@message}</div>
                    </div>
                  <% end %>
                </div>
              </div>
            <% end %>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end
end
