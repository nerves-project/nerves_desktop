defmodule NervesDesktopWeb.BurnerLive do
  use NervesDesktopWeb, :live_view

  alias NervesBurner.FirmwareImages
  alias NervesBurner.Fwup
  alias NervesBurner.Downloader

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Initial scan
      send(self(), :scan_devices)
    end

    {:ok,
     socket
     |> assign(images: FirmwareImages.list())
     |> assign(selected_image: nil)
     |> assign(selected_target_arch: nil) # Nerves Hardware Target (e.g. rpi4)
     |> assign(selected_device: nil)      # Storage Device path
     |> assign(devices: [])
     |> assign(status: :idle) # :idle, :downloading, :burning, :success, :error
     |> assign(message: "")
     |> assign(progress: 0)}
  end

  @impl true
  def handle_info(:scan_devices, socket) do
    case Fwup.scan_devices() do
      {:ok, devices} -> {:noreply, assign(socket, devices: devices)}
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:burn_result, result}, socket) do
    case result do
      :ok ->
        {:noreply, assign(socket, status: :success, message: "Firmware burned successfully!", progress: 100)}
      {:error, reason} ->
        {:noreply, assign(socket, status: :error, message: "Burn failed: #{inspect(reason)}")}
    end
  end

  @impl true
  def handle_info({:update_status, status, message}, socket) do
    progress = case status do
      :downloading -> 25
      :burning -> 75
      _ -> 0
    end
    {:noreply, assign(socket, status: status, message: message, progress: progress)}
  end

  @impl true
  def handle_event("select_image", %{"name" => name}, socket) do
    {name, config} = Enum.find(socket.assigns.images, fn {n, _} -> n == name end)
    # Default to first target if available
    target_arch = List.first(config.targets)
    {:noreply, assign(socket, selected_image: {name, config}, selected_target_arch: target_arch, selected_device: nil)}
  end

  @impl true
  def handle_event("select_target_arch", %{"arch" => arch}, socket) do
    {:noreply, assign(socket, selected_target_arch: arch)}
  end

  @impl true
  def handle_event("select_device", %{"path" => path}, socket) do
    {:noreply, assign(socket, selected_device: path)}
  end

  @impl true
  def handle_event("refresh_devices", _params, socket) do
    send(self(), :scan_devices)
    {:noreply, socket}
  end

  @impl true
  def handle_event("burn", _params, %{assigns: %{selected_image: {_name, config}, selected_target_arch: arch, selected_device: device_path}} = socket) do
    parent = self()
    Task.start_link(fn ->
      try do
        send(parent, {:update_status, :downloading, "Downloading firmware for #{arch}..."})
        {:ok, fw_path} = Downloader.download(config, arch)
        
        send(parent, {:update_status, :burning, "Burning to #{device_path}..."})
        result = NervesDesktop.Fwup.burn(fw_path, device_path)
        
        send(parent, {:burn_result, result})
      rescue
        e -> send(parent, {:burn_result, {:error, e}})
      end
    end)

    {:noreply, assign(socket, status: :started, message: "Starting process...", progress: 10)}
  end

  defp format_size(bytes) when is_integer(bytes) do
    cond do
      bytes >= 1_000_000_000 -> "#{Float.round(bytes / 1_000_000_000, 2)} GB"
      bytes >= 1_000_000 -> "#{Float.round(bytes / 1_000_000, 2)} MB"
      bytes >= 1_000 -> "#{Float.round(bytes / 1_000, 2)} KB"
      true -> "#{bytes} B"
    end
  end
  defp format_size(_), do: "Unknown size"

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:burner}>
      <div class="p-4 md:p-8 w-full">
        <header class="mb-10">
          <h1 class="text-4xl font-extrabold tracking-tight text-gray-900 flex items-center gap-3">
            <div class="p-2 bg-primary/10 rounded-xl text-primary">
              <.icon name="hero-fire" class="w-10 h-10" />
            </div>
            Firmware Burner
          </h1>
          <p class="text-lg text-gray-500 mt-2 font-medium">
            Download and flash Nerves firmware to SD cards
          </p>
        </header>

        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <!-- Selection Section -->
          <div class="space-y-6">
            <div class="bg-white p-6 rounded-[2rem] shadow-xl shadow-gray-200/50 border border-gray-100">
              <h3 class="text-xl font-bold text-gray-900 mb-6 flex items-center gap-2">
                <span class="w-8 h-8 rounded-full bg-primary/10 text-primary flex items-center justify-center text-sm">1</span>
                Select Firmware
              </h3>
              
              <div class="grid grid-cols-1 gap-3">
                <%= for {name, config} <- @images do %>
                  <button
                    phx-click="select_image"
                    phx-value-name={name}
                    class={[
                      "text-left p-4 rounded-2xl border-2 transition-all group",
                      (elem(@selected_image || {"", nil}, 0) == name && "border-primary bg-primary/5") || "border-gray-50 hover:border-primary/30 hover:bg-gray-50"
                    ]}
                  >
                    <div class="font-bold text-gray-900 group-hover:text-primary transition-colors">{name}</div>
                    <div class="text-xs text-gray-500 mt-1">{config.description}</div>
                  </button>
                <% end %>
              </div>
            </div>

            <div class="bg-white p-6 rounded-[2rem] shadow-xl shadow-gray-200/50 border border-gray-100">
              <h3 class="text-xl font-bold text-gray-900 mb-6 flex items-center gap-2">
                <span class="w-8 h-8 rounded-full bg-primary/10 text-primary flex items-center justify-center text-sm">2</span>
                Select Hardware Target
              </h3>
              
              <%= if @selected_image do %>
                <div class="flex flex-wrap gap-2 animate-in fade-in duration-500">
                  <%= for arch <- elem(@selected_image, 1).targets do %>
                    <button
                      phx-click="select_target_arch"
                      phx-value-arch={arch}
                      class={[
                        "px-4 py-2 rounded-xl border-2 text-sm font-bold transition-all",
                        (@selected_target_arch == arch && "border-primary bg-primary text-white shadow-md shadow-primary/20") || "border-gray-50 bg-gray-50 text-gray-500 hover:border-primary/30"
                      ]}
                    >
                      {arch}
                    </button>
                  <% end %>
                </div>
              <% else %>
                <div class="p-6 text-center bg-gray-50 rounded-2xl border-2 border-dashed border-gray-100 text-gray-400">
                  <p class="text-sm font-medium">Please select a firmware image in Step 1 first to see available hardware targets.</p>
                </div>
              <% end %>
            </div>

            <div class="bg-white p-6 rounded-[2rem] shadow-xl shadow-gray-200/50 border border-gray-100">
              <div class="flex justify-between items-center mb-6">
                <h3 class="text-xl font-bold text-gray-900 flex items-center gap-2">
                  <span class="w-8 h-8 rounded-full bg-primary/10 text-primary flex items-center justify-center text-sm">3</span>
                  Select Storage Device
                </h3>
                <button phx-click="refresh_devices" class="btn btn-ghost btn-sm text-primary">
                  <.icon name="hero-arrow-path" class="w-4 h-4" /> Refresh
                </button>
              </div>

              <%= if Enum.empty?(@devices) do %>
                <div class="p-8 text-center bg-gray-50 rounded-2xl border-2 border-dashed border-gray-200 text-gray-400">
                  <p>No devices detected. Insert an SD card and refresh.</p>
                </div>
              <% else %>
                <div class="grid grid-cols-1 gap-3">
                  <%= for device <- @devices do %>
                    <button
                      phx-click="select_device"
                      phx-value-path={device.path}
                      class={[
                        "text-left p-4 rounded-2xl border-2 transition-all group",
                        (@selected_device == device.path && "border-primary bg-primary/5") || "border-gray-50 hover:border-primary/30 hover:bg-gray-50"
                      ]}
                    >
                      <div class="font-bold text-gray-900 group-hover:text-primary transition-colors">
                        {device[:description] || device.path}
                      </div>
                      <div class="text-xs font-mono text-gray-400 mt-1">
                        {device.path} &bull; {format_size(device[:size])}
                      </div>
                    </button>
                  <% end %>
                </div>
              <% end %>
            </div>
          </div>

          <!-- Action & Status Section -->
          <div class="space-y-6">
            <div class="bg-white p-8 rounded-[2rem] shadow-xl shadow-gray-200/50 border border-gray-100 flex flex-col h-full">
              <h3 class="text-xl font-bold text-gray-900 mb-8">Ready to Burn</h3>
              
              <div class="space-y-6 flex-1">
                <div class="flex items-center gap-4 p-4 bg-gray-50 rounded-2xl border border-gray-100 transition-all text-ellipsis overflow-hidden">
                  <div class="w-12 h-12 bg-white rounded-xl shadow-sm flex items-center justify-center shrink-0">
                    <.icon name="hero-document-text" class="w-6 h-6 text-gray-400" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="text-[10px] uppercase font-bold text-gray-400">Firmware</div>
                    <div class="font-bold text-gray-900 truncate">
                      {elem(@selected_image || {"None", nil}, 0)}
                      <span :if={@selected_target_arch} class="ml-2 text-primary font-mono text-xs bg-primary/10 px-2 py-0.5 rounded-lg shrink-0">{@selected_target_arch}</span>
                    </div>
                  </div>
                </div>

                <div class="flex items-center gap-4 p-4 bg-gray-50 rounded-2xl border border-gray-100">
                  <div class="w-12 h-12 bg-white rounded-xl shadow-sm flex items-center justify-center shrink-0">
                    <.icon name="hero-archive-box" class="w-6 h-6 text-gray-400" />
                  </div>
                  <div class="flex-1 min-w-0">
                    <div class="text-[10px] uppercase font-bold text-gray-400">Storage Device</div>
                    <div class="font-bold text-gray-900 truncate">{@selected_device || "None Selected"}</div>
                  </div>
                </div>

                <%= if @status != :idle do %>
                  <div class="pt-8 animate-in fade-in duration-500">
                    <div class="flex justify-between items-end mb-2">
                      <div class="text-sm font-bold text-gray-900">{@message}</div>
                      <div class="text-xs font-mono text-gray-400">{@progress}%</div>
                    </div>
                    <div class="w-full bg-gray-100 rounded-full h-3 overflow-hidden shadow-inner">
                      <div
                        class="bg-primary h-full transition-all duration-500 rounded-full shadow-lg shadow-primary/30"
                        style={"width: #{@progress}%"}
                      ></div>
                    </div>
                  </div>
                <% end %>

                <%= if @status == :success do %>
                  <div class="mt-4 p-4 bg-green-50 text-green-700 rounded-2xl border border-green-100 flex items-center gap-3 animate-bounce">
                    <.icon name="hero-check-circle" class="w-6 h-6" />
                    <div class="text-sm font-bold">Successfully flashed! You can now eject the storage device.</div>
                  </div>
                <% end %>

                <%= if @status == :error do %>
                  <div class="mt-4 p-4 bg-red-50 text-red-700 rounded-2xl border border-red-100 flex items-center gap-3">
                    <.icon name="hero-exclamation-triangle" class="w-6 h-6" />
                    <div class="text-sm font-bold">{@message}</div>
                  </div>
                <% end %>
              </div>

              <div class="mt-12">
                <button
                  phx-click="burn"
                  disabled={is_nil(@selected_image) or is_nil(@selected_device) or @status in [:downloading, :burning]}
                  class="btn btn-primary w-full h-16 rounded-2xl text-lg font-black shadow-lg shadow-primary/20 disabled:bg-gray-100 disabled:text-gray-400 disabled:shadow-none transition-all hover:scale-[1.01] active:scale-[0.99]"
                >
                  <%= if @status in [:downloading, :burning] do %>
                    <span class="loading loading-spinner"></span> Processing...
                  <% else %>
                    <.icon name="hero-fire" class="w-6 h-6" /> START BURNING
                  <% end %>
                </button>
                <p class="text-center text-[10px] text-gray-400 mt-4 uppercase tracking-widest font-bold">
                  WARNING: ALL DATA ON THE STORAGE DEVICE WILL BE ERASED
                </p>
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
