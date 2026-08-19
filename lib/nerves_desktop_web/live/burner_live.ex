defmodule NervesDesktopWeb.BurnerLive do
  use NervesDesktopWeb, :live_view
  require Logger

  alias NervesBurner.FirmwareImages
  alias NervesDesktop.Native

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      send(self(), :scan_devices)
      Native.subscribe("file_dialog_result")
    end

    {:ok,
     socket
     |> assign(page_title: "Firmware")
     |> assign(images: FirmwareImages.list())
     |> assign(selected_image: nil)
     |> assign(selected_target_arch: nil)
     |> assign(selected_device: nil)
     |> assign(devices: [])
     |> assign(status: :idle)
     |> assign(message: "")
     |> assign(progress: 0)
     |> assign(wifi_ssid: "")
     |> assign(wifi_psk: "")
     |> assign(wifi_form: to_form(%{"ssid" => "", "psk" => ""}, as: :wifi))
     |> assign(last_write: nil)
     |> assign(native?: Native.available?())
     |> assign(fwup_installed?: not is_nil(System.find_executable("fwup")))
     |> assign(host_info: NervesDesktop.HostInfo.get())}
  end

  @impl true
  def handle_info(:scan_devices, socket) do
    fwup_installed? = not is_nil(System.find_executable("fwup"))

    devices =
      if fwup_installed? do
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
      else
        []
      end

    {:noreply, assign(socket, devices: devices, fwup_installed?: fwup_installed?)}
  end

  @impl true
  def handle_info(path, socket) when is_binary(path) do
    Logger.info("[Burner] Local firmware selected: #{path}")

    {:noreply,
     socket
     |> clear_outcome()
     |> assign(selected_image: {:local, path})
     |> assign(selected_target_arch: nil)}
  end

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
    written = %{
      image: image_name(socket.assigns.selected_image),
      device: socket.assigns.selected_device
    }

    send(self(), :scan_devices)

    {:noreply,
     socket
     |> assign(status: :success, progress: 100, last_write: written)
     |> assign(selected_image: nil, selected_target_arch: nil, selected_device: nil)}
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

  @impl true
  def handle_info({:download_progress, percent}, socket) do
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
     |> clear_outcome()
     |> assign(selected_image: {name, config}, selected_target_arch: target_arch)}
  end

  @impl true
  def handle_event("open_url", %{"url" => url}, socket) do
    Native.broadcast("opener", url)
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_local_firmware", _params, socket) do
    Native.broadcast("messages", "open_file_dialog")
    {:noreply, socket}
  end

  @impl true
  def handle_event("select_target_arch", %{"arch" => arch}, socket) do
    {:noreply, socket |> clear_outcome() |> assign(selected_target_arch: arch)}
  end

  @impl true
  def handle_event("select_device", %{"path" => path}, socket) do
    {:noreply, socket |> clear_outcome() |> assign(selected_device: path)}
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
      <UI.page_header title="Firmware" subtitle="Write a Nerves image onto an SD card" />

      <UI.panel :if={!@fwup_installed?} label="fwup is missing" body_class="p-5">
        <p class="max-w-2xl text-[13px] leading-relaxed">
          Writing an image needs <UI.code text="fwup" />, which is not on
          your PATH. Install it and come back to this page.
        </p>

        <div class="mt-4 grid grid-cols-1 gap-2 sm:grid-cols-3">
          <div :for={{os, cmd} <- install_commands()} class="nd-well p-3">
            <p class="nd-label">{os}</p>
            <code class="mt-1.5 block font-mono text-xs break-all text-ink">{cmd}</code>
          </div>
        </div>

        <a
          href="https://github.com/fwup-home/fwup"
          phx-hook="TauriOpen"
          id="fwup-repo-link"
          class="mt-4 inline-flex items-center gap-1.5 text-[13px] font-semibold text-primary hover:underline"
        >
          Other install methods on GitHub
          <.icon name="hero-arrow-top-right-on-square" class="size-3.5" />
        </a>
      </UI.panel>

      <div class={[
        "grid grid-cols-1 items-start gap-5 xl:grid-cols-2",
        !@fwup_installed? && "pointer-events-none opacity-40"
      ]}>
        <div class="space-y-5">
          <UI.panel step={1} done={not is_nil(@selected_image)} label="Pick the firmware">
            <:actions>
              <button
                phx-click="select_local_firmware"
                disabled={!@native?}
                title={!@native? && "Choosing a file needs the desktop app"}
                class="nd-btn nd-btn-ghost h-7 disabled:bg-transparent disabled:text-faint"
              >
                <.icon name="hero-folder-open" class="size-3.5" /> Open file
              </button>
            </:actions>

            <div class="space-y-2">
              <div
                :if={match?({:local, _}, @selected_image)}
                class="flex items-center gap-2.5 rounded-md border border-primary bg-primary-soft p-3"
              >
                <.icon name="hero-document-check" class="size-4 shrink-0 text-primary" />
                <div class="min-w-0">
                  <p class="truncate text-[13px] font-semibold">
                    {Path.basename(elem(@selected_image, 1))}
                  </p>
                  <p class="truncate font-mono text-xs text-muted">{elem(@selected_image, 1)}</p>
                </div>
              </div>

              <button
                :for={{name, config} <- @images}
                phx-click="select_image"
                phx-value-name={name}
                aria-pressed={match?({^name, _}, @selected_image)}
                class={[
                  "block w-full rounded-md border p-3 text-left transition-colors",
                  (match?({^name, _}, @selected_image) && "border-primary bg-primary-soft") ||
                    "border-rule hover:border-primary hover:bg-sunk"
                ]}
              >
                <span class="text-[13px] font-semibold">{name}</span>
                <span class="mt-0.5 block text-xs text-muted">{config.description}</span>
              </button>
            </div>
          </UI.panel>

          <UI.panel
            step={2}
            done={not is_nil(@selected_target_arch) or match?({:local, _}, @selected_image)}
            label="Pick the board it runs on"
          >
            <%= if is_tuple(@selected_image) and elem(@selected_image, 0) != :local do %>
              <div class="flex flex-wrap gap-1.5">
                <button
                  :for={arch <- elem(@selected_image, 1).targets}
                  phx-click="select_target_arch"
                  phx-value-arch={arch}
                  aria-pressed={@selected_target_arch == arch}
                  class={[
                    "nd-btn h-8 font-mono text-xs",
                    (@selected_target_arch == arch && "nd-btn-primary") || "nd-btn-secondary"
                  ]}
                >
                  {arch}
                </button>
              </div>
            <% else %>
              <UI.placeholder icon="hero-arrow-up">
                {if match?({:local, _}, @selected_image),
                  do: "A file from disk already carries its target.",
                  else: "Pick the firmware first."}
              </UI.placeholder>
            <% end %>
          </UI.panel>

          <UI.panel step={3} done={not is_nil(@selected_device)} label="Pick the card to write">
            <:actions>
              <button phx-click="refresh_devices" class="nd-btn nd-btn-ghost h-7">
                <.icon name="hero-arrow-path" class="size-3.5" /> Rescan
              </button>
            </:actions>

            <%= if Enum.empty?(@devices) do %>
              <UI.placeholder icon="hero-inbox">
                No removable card found. Insert one and rescan.
              </UI.placeholder>
            <% else %>
              <div class="space-y-2">
                <button
                  :for={device <- @devices}
                  phx-click="select_device"
                  phx-value-path={device.path}
                  aria-pressed={@selected_device == device.path}
                  class={[
                    "block w-full rounded-md border p-3 text-left transition-colors",
                    (@selected_device == device.path && "border-primary bg-primary-soft") ||
                      "border-rule hover:border-primary hover:bg-sunk"
                  ]}
                >
                  <span class="text-[13px] font-semibold">
                    {device[:description] || device.path}
                  </span>
                  <span class="mt-0.5 block font-mono text-xs text-muted">
                    {device.path} &middot; {format_size(device[:size])}
                  </span>
                </button>
              </div>
            <% end %>
          </UI.panel>
        </div>

        <UI.panel
          label="Check it over"
          class="xl:sticky xl:top-6"
          body_class="flex flex-col gap-4 p-4"
        >
          <dl class="divide-y divide-rule rounded-md border border-rule">
            <div class="flex items-baseline gap-3 px-3 py-2.5">
              <dt class="nd-label w-20 shrink-0">Image</dt>
              <dd class="min-w-0 flex-1 text-[13px]">
                <span class={[
                  "font-semibold",
                  is_nil(@selected_image) && "font-normal text-faint"
                ]}>
                  <%= case @selected_image do %>
                    <% {:local, path} -> %>
                      {Path.basename(path)}
                    <% {name, _} -> %>
                      {name}
                    <% _ -> %>
                      Not chosen
                  <% end %>
                </span>
                <span :if={@selected_target_arch} class="nd-chip nd-chip-signal ml-1.5">
                  {@selected_target_arch}
                </span>
              </dd>
            </div>

            <div class="flex items-baseline gap-3 px-3 py-2.5">
              <dt class="nd-label w-20 shrink-0">Card</dt>
              <dd class={[
                "min-w-0 flex-1 truncate font-mono text-[13px]",
                (@selected_device && "font-medium") || "text-faint"
              ]}>
                {@selected_device || "Not chosen"}
              </dd>
            </div>
          </dl>

          <div class="nd-well p-3">
            <p class="nd-legend mb-3">
              <span>Wi-Fi, if the board needs it</span>
            </p>

            <.form for={@wifi_form} id="wifi-form" phx-change="update_wifi" class="grid gap-2.5">
              <.input
                field={@wifi_form[:ssid]}
                label="Network name"
                placeholder="MyHomeWiFi"
                autocomplete="off"
              />
              <.input
                field={@wifi_form[:psk]}
                type="password"
                label="Network password"
                placeholder="Leave blank for an open network"
                autocomplete="off"
              />
            </.form>
            <p class="mt-2 text-xs text-muted">
              Written into the image in the clear, so anyone holding the card can read them.
            </p>
          </div>

          <div :if={writing?(@status)} aria-live="polite">
            <div class="mb-1.5 flex items-baseline justify-between gap-3">
              <span class="text-[13px] font-semibold">{@message}</span>
              <span class="font-mono text-xs text-muted">{@progress}%</span>
            </div>
            <div
              class="h-1.5 overflow-hidden rounded-full bg-rule"
              role="progressbar"
              aria-valuenow={@progress}
              aria-valuemin="0"
              aria-valuemax="100"
            >
              <div
                class="h-full rounded-full bg-secondary shadow-[0_0_8px_0_var(--color-secondary)] transition-[width] duration-500"
                style={"width: #{@progress}%"}
              >
              </div>
            </div>
          </div>

          <div
            :if={@status == :success && @last_write}
            class="nd-note nd-note-live"
            role="status"
            aria-live="polite"
          >
            <.icon name="hero-check-circle" class="mt-px size-4 shrink-0 text-live" />
            <span>
              Wrote <span class="font-semibold">{@last_write.image}</span>
              to <span class="font-mono font-semibold">{@last_write.device}</span>.
              The card is unmounted, so you can pull it out now.
            </span>
          </div>

          <div :if={@status == :error} class="nd-note nd-note-danger">
            <.icon name="hero-exclamation-triangle" class="mt-px size-4 shrink-0 text-danger" />
            <span>{@message}</span>
          </div>

          <div class="mt-auto space-y-3 border-t border-rule pt-4">
            <div class="nd-note nd-note-danger">
              <.icon name="hero-exclamation-triangle" class="mt-px size-4 shrink-0 text-danger" />
              <span :if={@selected_device}>
                Flashing to <span class="font-mono font-semibold">{@selected_device}</span>
                erases the card. Everything already on it will be lost.
              </span>
              <span :if={is_nil(@selected_device)}>
                Flashing erases the card you choose. Everything already on it will be lost.
              </span>
            </div>

            <button
              phx-click="burn"
              disabled={
                !@fwup_installed? or is_nil(@selected_image) or is_nil(@selected_device) or
                  writing?(@status)
              }
              class="nd-btn nd-btn-danger nd-btn-lg w-full"
            >
              <%= if writing?(@status) do %>
                <.icon name="hero-arrow-path" class="size-4 motion-safe:animate-spin" /> Writing…
              <% else %>
                <.icon name="hero-bolt" class="size-4" /> Erase card and write firmware
              <% end %>
            </button>
          </div>
        </UI.panel>
      </div>
    </Layouts.app>
    """
  end

  @doc false
  def writing?(status), do: status in [:downloading, :burning]

  defp clear_outcome(%{assigns: %{status: status}} = socket) when status in [:success, :error] do
    Phoenix.Component.assign(socket, status: :idle, progress: 0, message: "", last_write: nil)
  end

  defp clear_outcome(socket), do: socket

  defp image_name({:local, path}), do: Path.basename(path)
  defp image_name({name, _config}), do: name
  defp image_name(_), do: "the firmware"

  defp install_commands do
    [
      {"macOS", "brew install fwup"},
      {"Linux", "sudo apt install fwup"},
      {"Windows", "choco install fwup"}
    ]
  end
end
