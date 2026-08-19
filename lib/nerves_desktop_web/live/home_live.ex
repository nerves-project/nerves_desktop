defmodule NervesDesktopWeb.HomeLive do
  use NervesDesktopWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "discovery")
    end

    {:ok,
     socket
     |> assign(page_title: "Devices")
     |> assign(mdns_snippet: mount_snippet())
     |> assign(mdns_html: NervesDesktopWeb.ElixirSnippet.to_html(mount_snippet()))
     |> assign(devices: NervesDesktop.DeviceScanner.get_devices())
     |> assign(last_scan_at: DateTime.utc_now())}
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, assign(socket, devices: devices, last_scan_at: DateTime.utc_now())}
  end

  @impl true
  def handle_event("scan_now", _params, socket) do
    NervesDesktop.DeviceScanner.scan_now()
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:devices}>
      <UI.page_header
        title="Devices"
        subtitle={device_summary(@devices)}
      >
        <:actions>
          <UI.scanning_status last_scan_at={@last_scan_at} on_refresh="scan_now" />
        </:actions>
      </UI.page_header>

      <%= if Enum.empty?(@devices) do %>
        <UI.panel body_class="p-0">
          <div class="flex flex-col items-center px-6 py-10 text-center">
            <.icon name="hero-cpu-chip" class="size-9 text-rule-strong" />
            <h2 class="mt-3 font-display text-lg font-semibold">No devices found</h2>
            <p class="mt-1.5 max-w-md text-[13px] leading-relaxed text-muted">
              Nothing has responded on your network or on a serial port. Scanning keeps
              running, so a device will appear here as soon as it answers.
            </p>
          </div>

          <div class="border-t border-rule px-5 py-4">
            <p class="nd-legend mb-1">
              <span>Why a device might not appear</span>
            </p>

            <dl class="divide-y divide-rule">
              <div class="grid grid-cols-[7.5rem_1fr] gap-4 py-3">
                <dt class="text-[13px] font-semibold">Network</dt>
                <dd class="text-[13px] leading-relaxed text-muted">
                  Discovery uses mDNS, which does not cross subnets and is blocked by most
                  VPNs. Keep the device and this computer on the same network.
                </dd>
              </div>
              <div class="grid grid-cols-[7.5rem_1fr] gap-4 py-3">
                <dt class="text-[13px] font-semibold">Boot time</dt>
                <dd class="text-[13px] leading-relaxed text-muted">
                  A device only answers once its network is up, which is a few seconds after
                  you power it on.
                </dd>
              </div>
              <div class="grid grid-cols-[7.5rem_1fr] gap-4 py-3">
                <dt class="text-[13px] font-semibold">No network</dt>
                <dd class="text-[13px] leading-relaxed text-muted">
                  Connect the device over USB instead. It shows up here as a serial device
                  and needs no network at all.
                </dd>
              </div>
            </dl>
          </div>
        </UI.panel>
      <% else %>
        <UI.panel body_class="">
          <div class="overflow-x-auto">
            <table class="w-full min-w-[42rem] border-collapse text-left">
              <thead>
                <tr class="border-b border-rule">
                  <th class="nd-label px-4 py-2">Device</th>
                  <th class="nd-label px-4 py-2">Address</th>
                  <th class="nd-label px-4 py-2">Firmware</th>
                  <th class="nd-label px-4 py-2 text-right">
                    <span class="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-rule">
                <tr :for={device <- @devices} class="group transition-colors hover:bg-sunk">
                  <td class="px-4 py-3">
                    <div class="font-semibold">{device[:name]}</div>
                    <UI.copyable value={device[:hostname]} class="mt-0.5" />
                  </td>
                  <td class="px-4 py-3">
                    <div class="flex items-center gap-2">
                      <span class={[
                        "nd-chip",
                        (device[:type] == :uart && "nd-chip-serial") || "nd-chip-signal"
                      ]}>
                        <span class="nd-led"></span>
                        {if device[:type] == :uart, do: "Serial", else: "Network"}
                      </span>
                      <UI.copyable value={device[:ip] || device[:target]} />
                    </div>
                  </td>
                  <td class="px-4 py-3">
                    <div class="text-[13px] font-semibold">{device[:product] || "Unknown"}</div>
                    <div class="mt-0.5 flex items-center gap-1.5 font-mono text-xs whitespace-nowrap text-muted">
                      <span>{device[:version] || "no version"}</span>
                      <span :if={device[:platform]} class="text-rule-strong">/</span>
                      <span :if={device[:platform]}>{device[:platform]}</span>
                    </div>
                  </td>
                  <td class="px-4 py-3 text-right">
                    <.link
                      navigate={
                        ~p"/console?target=#{device[:target]}&name=#{device[:name] || device[:hostname]}"
                      }
                      class="nd-btn nd-btn-secondary group-hover:border-primary"
                    >
                      <.icon name="hero-command-line" class="size-4" /> Open console
                    </.link>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </UI.panel>
      <% end %>

      <UI.panel label="Why some columns are empty" body_class="p-5">
        <:actions>
          <button
            phx-click={JS.dispatch("phx:copy", detail: %{text: @mdns_snippet})}
            class="nd-btn nd-btn-ghost h-7"
          >
            <.icon name="hero-clipboard" class="size-3.5" /> Copy
          </button>
        </:actions>

        <p class="max-w-3xl text-[13px] leading-relaxed text-muted">
          A device only advertises what it is told to, which by default is not much. Register
          the service in
          <code class="rounded-sm bg-primary-soft px-1 font-mono text-xs text-primary">
            Application.start/2
          </code>
          and its product, version, and platform fill in here.
        </p>

        <pre class="nd-well nd-code mt-4 overflow-x-auto p-4"><code>{@mdns_html}</code></pre>
      </UI.panel>
    </Layouts.app>
    """
  end

  defp device_summary([]), do: "Scanning the network and your serial ports"
  defp device_summary([_]), do: "1 device found"
  defp device_summary(devices), do: "#{length(devices)} devices found"

  defp mount_snippet do
    """
    MdnsLite.add_mdns_service(%{
      id: :nerves_device,
      protocol: "nerves-device",
      transport: "tcp",
      port: 0,
      txt_payload: [
        "serial=\#{Nerves.Runtime.serial_number()}",
        "product=\#{Nerves.Runtime.KV.get_active(\"nerves_fw_product\")}",
        "description=\#{Nerves.Runtime.KV.get_active(\"nerves_fw_description\")}",
        "version=\#{Nerves.Runtime.KV.get_active(\"nerves_fw_version\")}",
        "platform=\#{Nerves.Runtime.KV.get_active(\"nerves_fw_platform\")}",
        "architecture=\#{Nerves.Runtime.KV.get_active(\"nerves_fw_architecture\")}",
        "author=\#{Nerves.Runtime.KV.get_active(\"nerves_fw_author\")}",
        "uuid=\#{Nerves.Runtime.KV.get_active(\"nerves_fw_uuid\")}"
      ]
    })
    """
  end
end
