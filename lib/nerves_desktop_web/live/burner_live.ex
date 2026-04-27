defmodule NervesDesktopWeb.BurnerLive do
  use NervesDesktopWeb, :live_view
  require Logger

  alias NervesBurner.FirmwareImages

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Initial scan
      send(self(), :scan_devices)
      # Subscribe to file dialog result from Rust
      ElixirKit.PubSub.subscribe("file_dialog_result")
    end

    {:ok,
     socket
     |> assign(images: FirmwareImages.list())
     |> assign(selected_image: nil)
     |> assign(selected_target_arch: nil)
     |> assign(selected_device: nil)
     |> assign(devices: [])
     |> assign(status: :idle)
     |> assign(message: "")
     |> assign(progress: 0)
     # WiFi Provisioning
     |> assign(wifi_ssid: "")
     |> assign(wifi_psk: "")
     |> assign(wifi_form: to_form(%{"ssid" => "", "psk" => ""}, as: :wifi))
     # System Status
     |> assign(fwup_installed?: not is_nil(System.find_executable("fwup")))
     |> assign(host_info: NervesDesktop.HostInfo.get())}
  end

  @impl true
  def handle_info(:scan_devices, socket) do
    devices =
      Fwup.get_devices()
      |> Enum.reject(&(&1 == [""]))
      |> Enum.map(fn
        [path, size | rest] ->
          description = if rest == [], do: path, else: Enum.join(rest, ", ")
          %{path: path, size: String.to_integer(size), description: description}

        _ ->
          nil
      end)
      |> Enum.reject(&is_nil/1)

    {:noreply, assign(socket, devices: devices)}
  end

  # Handle file dialog result from Rust
  @impl true
  def handle_info({:elixirkit_pubsub, "file_dialog_result", path_bytes}, socket) do
    path = List.to_string(path_bytes)
    Logger.info("[Burner] Local firmware selected: #{path}")

    {:noreply,
     socket
     |> assign(selected_image: {:local, path})
     |> assign(selected_target_arch: nil)}
  end

  # Handle progress from Fwup.Stream
  @impl true
  def handle_info({:fwup, {:progress, p}}, socket) do
    total_progress =
      case socket.assigns.selected_image do
        {:local, _} -> p
        _remote -> 50 + div(p, 2)
      end

    {:noreply, assign(socket, progress: total_progress)}
  end

  @impl true
  def handle_info({:fwup, {:ok, _code, _msg}}, socket) do
    {:noreply,
     socket
     |> assign(status: :success, message: "Firmware burned successfully!", progress: 100)}
  end

  @impl true
  def handle_info({:fwup, {:error, _code, msg}}, socket) do
    {:noreply, assign(socket, status: :error, message: "Burn failed: #{msg}")}
  end

  @impl true
  def handle_info({:fwup, {:warning, _code, msg}}, socket) do
    Logger.warning("[Burner] Fwup warning: #{msg}")
    {:noreply, socket}
  end

  # Handle download progress from our custom Req downloader
  @impl true
  def handle_info({:download_progress, percent}, socket) do
    # Download is the first 50% of the bar
    total_progress = div(percent, 2)
    {:noreply, assign(socket, progress: total_progress)}
  end

  @impl true
  def handle_info({:download_finished, fw_path}, socket) do
    send(self(), {:start_burn, fw_path})
    {:noreply, socket}
  end

  @impl true
  def handle_info({:start_burn, fw_path}, socket) do
    device_path = socket.assigns.selected_device

    env = [
      {"NERVES_WIFI_SSID", socket.assigns.wifi_ssid},
      {"NERVES_WIFI_PASSPHRASE", socket.assigns.wifi_psk}
    ]

    # Use Fwup.stream to run the burn asynchronously
    Fwup.stream(self(), ["-a", "-d", device_path, "-i", fw_path, "-t", "complete"], fwup_env: env)

    {:noreply,
     socket
     |> assign(status: :burning, message: "Burning to #{device_path}...", progress: 50)}
  end

  @impl true
  def handle_event("select_image", %{"name" => name}, socket) do
    {name, config} = Enum.find(socket.assigns.images, fn {n, _} -> n == name end)
    target_arch = List.first(config.targets)

    {:noreply,
     socket
     |> assign(selected_image: {name, config}, selected_target_arch: target_arch)}
  end

  @impl true
  def handle_event("select_local_firmware", _params, socket) do
    ElixirKit.PubSub.broadcast("open_file_dialog", "")
    {:noreply, socket}
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
  def handle_event("update_wifi", %{"wifi" => %{"ssid" => ssid, "psk" => psk}}, socket) do
    {:noreply,
     socket
     |> assign(wifi_ssid: ssid, wifi_psk: psk)
     |> assign(wifi_form: to_form(%{"ssid" => ssid, "psk" => psk}, as: :wifi))}
  end

  @impl true
  def handle_event("burn", _params, socket) do
    case socket.assigns.selected_image do
      {:local, path} ->
        send(self(), {:start_burn, path})

        {:noreply,
         socket
         |> assign(status: :burning, message: "Burning local firmware...", progress: 0)}

      {_name, config} ->
        arch = socket.assigns.selected_target_arch
        # Start the custom download process
        start_download(config, arch)

        {:noreply,
         socket
         |> assign(
           status: :downloading,
           message: "Downloading firmware for #{arch}...",
           progress: 0
         )}
    end
  end

  defp start_download(config, arch) do
    parent = self()

    Task.start_link(fn ->
      result =
        NervesBurner.Downloader.download(config, arch,
          on_progress: fn total, current ->
            if total > 0 do
              percent = round(current / total * 100)
              send(parent, {:download_progress, percent})
            end
          end
        )

      case result do
        {:ok, fw_path} ->
          send(parent, {:download_finished, fw_path})

        {:error, reason} ->
          send(parent, {:fwup, {:error, 0, reason}})
      end
    end)
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
      <UI.page_header
        icon="hero-fire"
        title="Firmware Burner"
        subtitle="Download and flash Nerves firmware to SD cards"
      />

      <%= if !@fwup_installed? do %>
        <div class="bg-red-50 border-2 border-red-100 rounded-[2rem] p-8 mb-8">
          <div class="flex items-start gap-4">
            <div class="p-3 bg-red-100 rounded-2xl text-red-600">
              <.icon name="hero-exclamation-triangle" class="w-8 h-8" />
            </div>
            <div>
              <h3 class="text-xl font-bold text-red-900 mb-2">Fwup Not Found</h3>
              <p class="text-red-700 leading-relaxed mb-6">
                The <code>fwup</code>
                tool is required to flash Nerves firmware but was not found on your system path.
              </p>

              <div class="grid grid-cols-1 md:grid-cols-2 gap-6 mb-6">
                <div class="bg-white/50 p-4 rounded-xl border border-red-200">
                  <p class="text-xs font-black uppercase text-red-900 mb-2 tracking-widest">macOS</p>
                  <code class="text-sm font-mono text-red-800 bg-red-100/50 px-2 py-1 rounded">
                    brew install fwup
                  </code>
                </div>
                <div class="bg-white/50 p-4 rounded-xl border border-red-200">
                  <p class="text-xs font-black uppercase text-red-900 mb-2 tracking-widest">Linux</p>
                  <code class="text-sm font-mono text-red-800 bg-red-100/50 px-2 py-1 rounded">
                    sudo apt install fwup
                  </code>
                </div>
              </div>

              <a
                href="https://github.com/fwup-home/fwup"
                phx-hook="TauriOpen"
                id="fwup-repo-link"
                class="text-red-900 font-bold underline hover:no-underline"
              >
                Visit fwup repository for more instructions &rarr;
              </a>
            </div>
          </div>
        </div>
      <% end %>

      <div class={"grid grid-cols-1 lg:grid-cols-2 gap-8 #{if !@fwup_installed?, do: "opacity-50 pointer-events-none"}"}>
        <!-- Selection Section -->
        <div class="space-y-6">
          <UI.step_box step={1} title="Select Firmware">
            <:actions>
              <button
                phx-click="select_local_firmware"
                class="btn btn-ghost btn-sm text-primary flex items-center gap-2"
              >
                <.icon name="hero-folder-open" class="w-4 h-4" /> Select Local File
              </button>
            </:actions>

            <div class="grid grid-cols-1 gap-3">
              <%= if match?({:local, _}, @selected_image) do %>
                <div class="p-4 rounded-2xl border-2 border-primary bg-primary/5 flex items-center gap-3">
                  <.icon name="hero-document-check" class="w-6 h-6 text-primary" />
                  <div class="flex-1 min-w-0">
                    <div class="font-bold text-gray-900 truncate">
                      {Path.basename(elem(@selected_image, 1))}
                    </div>
                    <div class="text-xs text-gray-500 truncate">{elem(@selected_image, 1)}</div>
                  </div>
                </div>
              <% end %>

              <%= for {name, config} <- @images do %>
                <button
                  phx-click="select_image"
                  phx-value-name={name}
                  class={[
                    "text-left p-4 rounded-2xl border-2 transition-all group",
                    (match?({^name, _}, @selected_image) && "border-primary bg-primary/5") ||
                      "border-gray-50 hover:border-primary/30 hover:bg-gray-50"
                  ]}
                >
                  <div class="font-bold text-gray-900 group-hover:text-primary transition-colors">
                    {name}
                  </div>
                  <div class="text-xs text-gray-500 mt-1">{config.description}</div>
                </button>
              <% end %>
            </div>
          </UI.step_box>

          <UI.step_box
            step={2}
            title="Select Hardware Target"
            class={match?({:local, _}, @selected_image) && "opacity-40 grayscale pointer-events-none"}
          >
            <%= if is_tuple(@selected_image) and elem(@selected_image, 0) != :local do %>
              <div class="flex flex-wrap gap-2">
                <%= for arch <- elem(@selected_image, 1).targets do %>
                  <button
                    phx-click="select_target_arch"
                    phx-value-arch={arch}
                    class={[
                      "px-4 py-2 rounded-xl border-2 text-sm font-bold transition-all",
                      (@selected_target_arch == arch &&
                         "border-primary bg-primary text-white shadow-md shadow-primary/20") ||
                        "border-gray-50 bg-gray-50 text-gray-500 hover:border-primary/30"
                    ]}
                  >
                    {arch}
                  </button>
                <% end %>
              </div>
            <% else %>
              <UI.placeholder>
                <p>
                  {if match?({:local, _}, @selected_image),
                    do: "Target selection not required for local firmware.",
                    else: "Please select a firmware image in Step 1 first."}
                </p>
              </UI.placeholder>
            <% end %>
          </UI.step_box>

          <UI.step_box step={3} title="Select Storage Device">
            <:actions>
              <button phx-click="refresh_devices" class="btn btn-ghost btn-sm text-primary">
                <.icon name="hero-arrow-path" class="w-4 h-4" /> Refresh
              </button>
            </:actions>

            <%= if Enum.empty?(@devices) do %>
              <UI.placeholder>
                <p>No devices detected. Insert an SD card and refresh.</p>
              </UI.placeholder>
            <% else %>
              <div class="grid grid-cols-1 gap-3">
                <%= for device <- @devices do %>
                  <button
                    phx-click="select_device"
                    phx-value-path={device.path}
                    class={[
                      "text-left p-4 rounded-2xl border-2 transition-all group",
                      (@selected_device == device.path && "border-primary bg-primary/5") ||
                        "border-gray-50 hover:border-primary/30 hover:bg-gray-50"
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
          </UI.step_box>
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
                    <%= case @selected_image do %>
                      <% {:local, path} -> %>
                        {Path.basename(path)}
                      <% {name, _} -> %>
                        {name}
                      <% _ -> %>
                        None Selected
                    <% end %>
                    <span
                      :if={@selected_target_arch}
                      class="ml-2 text-primary font-mono text-xs bg-primary/10 px-2 py-0.5 rounded-lg shrink-0"
                    >
                      {@selected_target_arch}
                    </span>
                  </div>
                </div>
              </div>

              <div class="flex items-center gap-4 p-4 bg-gray-50 rounded-2xl border border-gray-100">
                <div class="w-12 h-12 bg-white rounded-xl shadow-sm flex items-center justify-center shrink-0">
                  <.icon name="hero-archive-box" class="w-6 h-6 text-gray-400" />
                </div>
                <div class="flex-1 min-w-0">
                  <div class="text-[10px] uppercase font-bold text-gray-400">Storage Device</div>
                  <div class="font-bold text-gray-900 truncate">
                    {@selected_device || "None Selected"}
                  </div>
                </div>
              </div>
              
    <!-- WiFi Provisioning Form -->
              <div class="p-6 bg-gray-50 rounded-[2rem] border border-gray-100 space-y-4">
                <h4 class="text-xs font-black uppercase text-gray-400 tracking-widest flex items-center gap-2">
                  <.icon name="hero-wifi" class="w-4 h-4" /> WiFi Provisioning (Optional)
                </h4>

                <.form for={@wifi_form} phx-change="update_wifi" class="grid grid-cols-1 gap-2">
                  <.input
                    field={@wifi_form[:ssid]}
                    label="Network SSID"
                    placeholder="e.g. MyHomeWiFi"
                    autocomplete="off"
                  />
                  <.input
                    field={@wifi_form[:psk]}
                    type="password"
                    label="WiFi Password"
                    placeholder="••••••••"
                    autocomplete="off"
                  />
                </.form>
                <p class="text-[10px] text-gray-400 italic">
                  If provided, these will be baked into the burned firmware.
                </p>
              </div>

              <%= if @status != :idle do %>
                <div class="pt-8">
                  <div class="flex justify-between items-end mb-2">
                    <div class="text-sm font-bold text-gray-900">{@message}</div>
                    <div class="text-xs font-mono text-gray-400">{@progress}%</div>
                  </div>
                  <div class="w-full bg-gray-100 rounded-full h-3 overflow-hidden shadow-inner">
                    <div
                      class="bg-primary h-full transition-all duration-500 rounded-full shadow-lg shadow-primary/30"
                      style={"width: #{@progress}%"}
                    >
                    </div>
                  </div>
                </div>
              <% end %>

              <%= if @status == :success do %>
                <div class="mt-4 p-4 bg-green-50 text-green-700 rounded-2xl border border-green-100 flex items-center gap-3">
                  <.icon name="hero-check-circle" class="w-6 h-6" />
                  <div class="text-sm font-bold">
                    Successfully flashed! You can now eject the storage device.
                  </div>
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
                disabled={
                  is_nil(@selected_image) or is_nil(@selected_device) or
                    @status in [:downloading, :burning]
                }
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
    </Layouts.app>
    """
  end
end
