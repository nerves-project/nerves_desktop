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
        <div class="grid grid-cols-1 items-start gap-5 xl:grid-cols-2">
          <UI.panel label="Nothing has answered yet" body_class="p-5">
            <p class="text-[13px] leading-relaxed text-muted">
              The sweep runs every few seconds over mDNS and your serial ports. When a
              board is missing, it is almost always one of these.
            </p>

            <dl class="mt-4 divide-y divide-rule border-t border-rule">
              <div class="grid grid-cols-[9rem_1fr] gap-4 py-3">
                <dt class="text-[13px] font-semibold">Wrong network</dt>
                <dd class="text-[13px] leading-relaxed text-muted">
                  mDNS does not cross subnets, and most VPNs swallow it. Put the board and
                  this machine on the same LAN.
                </dd>
              </div>
              <div class="grid grid-cols-[9rem_1fr] gap-4 py-3">
                <dt class="text-[13px] font-semibold">Still booting</dt>
                <dd class="text-[13px] leading-relaxed text-muted">
                  A device only answers once its network stack is up, a few seconds after
                  power.
                </dd>
              </div>
              <div class="grid grid-cols-[9rem_1fr] gap-4 py-3">
                <dt class="text-[13px] font-semibold">No network at all</dt>
                <dd class="text-[13px] leading-relaxed text-muted">
                  Plug the board in over USB and it shows up here as a serial device
                  instead.
                </dd>
              </div>
            </dl>
          </UI.panel>

          <UI.panel label="Make a device say more about itself" body_class="p-5">
            <:actions>
              <button
                phx-click={JS.dispatch("phx:copy", detail: %{text: @mdns_snippet})}
                class="nd-btn nd-btn-ghost h-7"
              >
                <.icon name="hero-clipboard" class="size-3.5" /> Copy
              </button>
            </:actions>

            <p class="text-[13px] leading-relaxed text-muted">
              This list shows whatever a board advertises, which by default is not much.
              Register the service in
              <code class="rounded-sm bg-primary-soft px-1 font-mono text-xs text-primary">
                Application.start/2
              </code>
              and the product, version, and platform columns fill in.
            </p>

            <pre class="nd-well nd-code mt-4 overflow-x-auto p-4"><code>{@mdns_html}</code></pre>
          </UI.panel>
        </div>
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
    </Layouts.app>
    """
  end

  defp device_summary([]), do: "Sweeping the network and your serial ports"
  defp device_summary([_]), do: "One board answering"
  defp device_summary(devices), do: "#{length(devices)} boards answering"

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
