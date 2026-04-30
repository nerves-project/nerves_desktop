defmodule NervesDesktopWeb.HomeLive do
  use NervesDesktopWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "discovery")
    end

    {:ok,
     socket
     |> assign(mdns_snippet: mount_snippet())
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
        icon="hero-cpu-chip"
        title="Nerves Devices"
        subtitle="Monitor and discover Nerves nodes on your network"
      >
        <:actions>
          <UI.scanning_status last_scan_at={@last_scan_at} on_refresh="scan_now" />
        </:actions>
      </UI.page_header>

      <%= if Enum.empty?(@devices) do %>
        <div class="grid grid-cols-1 lg:grid-cols-2 gap-8 items-stretch">
          <div class="bg-white rounded-[2rem] p-12 flex flex-col items-center justify-center text-center shadow-xl shadow-gray-200/50 border border-gray-100">
            <div class="w-24 h-24 bg-gray-50 rounded-full flex items-center justify-center mb-6 relative">
              <.icon name="hero-magnifying-glass" class="w-12 h-12 text-gray-300" />
              <div class="absolute -top-1 -right-1">
                <span class="flex h-4 w-4">
                  <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-primary/40 opacity-75">
                  </span>
                  <span class="relative inline-flex rounded-full h-4 w-4 bg-primary/60"></span>
                </span>
              </div>
            </div>
            <h3 class="text-2xl font-bold text-gray-900">No devices found</h3>
            <p class="text-gray-500 mt-3 max-w-md leading-relaxed">
              We're currently scanning your network and serial ports for Nerves devices. If your device isn't showing up, try these steps:
            </p>

            <div class="mt-10 w-full grid grid-cols-1 md:grid-cols-3 gap-4">
              <div class="bg-gray-50 p-6 rounded-2xl border border-gray-100 text-left">
                <div class="w-10 h-10 bg-white rounded-lg shadow-sm flex items-center justify-center mb-4">
                  <.icon name="hero-wifi" class="w-6 h-6 text-primary" />
                </div>
                <h4 class="font-bold text-gray-900 text-sm mb-2">Network</h4>
                <p class="text-xs text-gray-500 leading-normal">
                  Ensure your device is on the same network.
                </p>
              </div>
              <div class="bg-gray-50 p-6 rounded-2xl border border-gray-100 text-left">
                <div class="w-10 h-10 bg-white rounded-lg shadow-sm flex items-center justify-center mb-4">
                  <svg
                    class="text-primary size-"
                    xmlns="http://www.w3.org/2000/svg"
                    width="24"
                    height="24"
                    viewBox="0 0 24 24"
                    fill="none"
                    stroke="currentColor"
                    stroke-width="1.4"
                    stroke-linecap="round"
                    stroke-linejoin="round"
                  >
                    <path d="M17 19a1 1 0 0 1-1-1v-2a2 2 0 0 1 2-2h2a2 2 0 0 1 2 2v2a1 1 0 0 1-1 1z" /><path d="M17 21v-2" /><path d="M19 14V6.5a1 1 0 0 0-7 0v11a1 1 0 0 1-7 0V10" /><path d="M21 21v-2" /><path d="M3 5V3" /><path d="M4 10a2 2 0 0 1-2-2V6a1 1 0 0 1 1-1h4a1 1 0 0 1 1 1v2a2 2 0 0 1-2 2z" /><path d="M7 5V3" />
                  </svg>
                </div>
                <h4 class="font-bold text-gray-900 text-sm mb-2">Serial</h4>
                <p class="text-xs text-gray-500 leading-normal">
                  Connect via USB to use UART console.
                </p>
              </div>
              <div class="bg-gray-50 p-6 rounded-2xl border border-gray-100 text-left">
                <div class="w-10 h-10 bg-white rounded-lg shadow-sm flex items-center justify-center mb-4">
                  <.icon name="hero-bolt" class="w-6 h-6 text-primary" />
                </div>
                <h4 class="font-bold text-gray-900 text-sm mb-2">Power</h4>
                <p class="text-xs text-gray-500 leading-normal">
                  Confirm your Nerves device is booted.
                </p>
              </div>
            </div>
          </div>

          <div class="bg-gray-50 rounded-[2rem] p-10 text-gray-900 shadow-xl shadow-gray-200/50 relative overflow-hidden flex flex-col border border-gray-100">
            <div class="absolute -top-10 -right-10 opacity-[0.03]">
              <.icon name="hero-code-bracket" class="w-64 h-64 text-gray-900" />
            </div>
            <div class="relative z-10 flex flex-col h-full">
              <div class="inline-flex w-fit px-3 py-1 rounded-full bg-primary/10 text-primary text-[10px] font-bold uppercase tracking-widest mb-6 border border-primary/20">
                Optimization
              </div>
              <h3 class="text-2xl font-bold mb-4">Enhance Discovery</h3>
              <p class="text-gray-500 mb-8 leading-relaxed">
                Add this snippet to your
                <code class="text-primary font-bold bg-primary/5 px-1 rounded">
                  Application.start/2
                </code>
                to share rich metadata via mDNS.
              </p>

              <div class="flex-1 bg-white rounded-2xl p-6 font-mono text-[11px] overflow-x-auto border border-gray-200 relative group shadow-inner">
                <button
                  phx-click={JS.dispatch("phx:copy", detail: %{text: @mdns_snippet})}
                  class="absolute top-4 right-4 p-2 bg-gray-50 hover:bg-gray-100 text-gray-400 hover:text-primary rounded-xl transition-all opacity-0 group-hover:opacity-100 border border-gray-200"
                  title="Copy code"
                >
                  <.icon name="hero-clipboard" class="w-5 h-5" />
                </button>
                <pre class="leading-relaxed"><code class="language-elixir text-gray-600">{@mdns_snippet}</code></pre>
              </div>
            </div>
          </div>
        </div>
      <% else %>
        <div class="bg-white rounded-[2rem] shadow-xl shadow-gray-200/50 border border-gray-100 overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-left border-collapse">
              <thead>
                <tr class="bg-gray-50/50 border-b border-gray-100">
                  <th class="px-8 py-5 text-xs uppercase tracking-widest font-bold text-gray-400">
                    Device Identity
                  </th>
                  <th class="px-8 py-5 text-xs uppercase tracking-widest font-bold text-gray-400">
                    Type / Address
                  </th>
                  <th class="px-8 py-5 text-xs uppercase tracking-widest font-bold text-gray-400">
                    Firmware Details
                  </th>
                  <th class="px-8 py-5 text-xs uppercase tracking-widest font-bold text-gray-400 text-right">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-gray-50">
                <%= for device <- @devices do %>
                  <tr class="hover:bg-primary/[0.02] transition-colors group">
                    <td class="px-8 py-4">
                      <div>
                        <div class="font-bold text-gray-900 text-base">{device[:name]}</div>
                        <div
                          class="text-xs text-gray-400 font-mono font-semibold flex items-center gap-1 cursor-pointer hover:text-primary transition-colors mt-0.5"
                          phx-click={
                            device[:hostname] &&
                              JS.dispatch("phx:copy", detail: %{text: device[:hostname]})
                          }
                        >
                          {device[:hostname] || "unknown"}
                          <.icon
                            :if={device[:hostname]}
                            name="hero-clipboard"
                            class="w-3 h-3 opacity-0 group-hover:opacity-100 transition-opacity"
                          />
                        </div>
                      </div>
                    </td>
                    <td class="px-8 py-4">
                      <div class="flex items-center gap-2 mb-1">
                        <span class={[
                          "px-2 py-0.5 rounded text-[10px] font-bold uppercase tracking-wider",
                          device[:type] == :network && "bg-blue-100 text-blue-700",
                          device[:type] == :uart && "bg-purple-100 text-purple-700"
                        ]}>
                          {device[:type]}
                        </span>
                      </div>
                      <div
                        phx-click={
                          JS.dispatch("phx:copy", detail: %{text: device[:ip] || device[:target]})
                        }
                        class="inline-flex items-center gap-2 px-2 py-1 -ml-2 text-xs font-mono font-semibold text-gray-400 hover:text-primary hover:bg-primary/5 rounded-lg cursor-pointer transition-all group/ip"
                        title="Click to copy"
                      >
                        {device[:ip] || device[:target]}
                        <.icon
                          name="hero-clipboard"
                          class="w-4 h-4 text-gray-300 group-hover/ip:text-primary transition-colors"
                        />
                      </div>
                    </td>
                    <td class="px-8 py-4">
                      <div class="text-gray-900 font-bold text-sm">
                        {device[:product] || "Unknown"}
                      </div>
                      <div class="flex items-center gap-2 mt-1 text-xs text-gray-400">
                        <span class="font-mono">{device[:version] || "---"}</span>
                        <span :if={device[:platform]} class="text-gray-200">•</span>
                        <span :if={device[:platform]}>{device[:platform]}</span>
                      </div>
                    </td>
                    <td class="px-8 py-4 text-right">
                      <.link
                        navigate={
                          ~p"/console?target=#{device[:target]}&name=#{device[:name] || device[:hostname]}"
                        }
                        class="btn btn-primary btn-md rounded-2xl flex items-center gap-2 w-fit ml-auto shadow-lg shadow-primary/20 transition-all hover:scale-[1.02] active:scale-[0.98]"
                      >
                        <.icon name="hero-command-line" class="w-5 h-5" /> Console
                      </.link>
                    </td>
                  </tr>
                <% end %>
              </tbody>
            </table>
          </div>
        </div>
      <% end %>
    </Layouts.app>
    """
  end

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
