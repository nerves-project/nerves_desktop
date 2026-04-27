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
      <div class="p-4 md:p-8 w-full">
        <header class="flex flex-col md:flex-row justify-between items-start md:items-center gap-4 mb-10">
          <div>
            <h1 class="text-4xl font-extrabold tracking-tight text-gray-900 flex items-center gap-3">
              <div class="p-2 bg-primary/10 rounded-xl">
                <.icon name="hero-cpu-chip" class="w-10 h-10 text-primary" />
              </div>
              Nerves Devices
            </h1>
            <p class="text-lg text-gray-500 mt-2 font-medium">
              Monitor and discover Nerves nodes on your network
            </p>
          </div>
          <UI.scanning_status last_scan_at={@last_scan_at} on_refresh="scan_now" />
        </header>

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
                We're currently scanning your network for Nerves devices. If your device isn't showing up, try these steps:
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
                    <.icon name="hero-shield-exclamation" class="w-6 h-6 text-primary" />
                  </div>
                  <h4 class="font-bold text-gray-900 text-sm mb-2">Firewall</h4>
                  <p class="text-xs text-gray-500 leading-normal">
                    Check if mDNS is blocked on UDP 5353.
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
                      Network Address
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
                      <td class="px-8 py-6">
                        <div class="flex items-center gap-4">
                          <div class="w-10 h-10 bg-gray-50 rounded-xl flex items-center justify-center border border-gray-100 group-hover:bg-white group-hover:shadow-sm transition-all">
                            <.icon
                              name="hero-cpu-chip"
                              class="w-5 h-5 text-gray-400 group-hover:text-primary"
                            />
                          </div>
                          <div>
                            <div class="font-bold text-gray-900 text-lg">{device.name}</div>
                            <div
                              class="text-xs text-gray-400 font-mono flex items-center gap-1 cursor-pointer hover:text-primary transition-colors mt-0.5"
                              phx-click={
                                device.hostname &&
                                  JS.dispatch("phx:copy", detail: %{text: device.hostname})
                              }
                            >
                              {device.hostname || "unknown"}
                              <.icon
                                :if={device.hostname}
                                name="hero-clipboard-document"
                                class="w-3 h-3 opacity-0 group-hover:opacity-100 transition-opacity"
                              />
                            </div>
                          </div>
                        </div>
                      </td>
                      <td class="px-8 py-6">
                        <div
                          class="inline-flex items-center gap-3 px-4 py-2 bg-gray-50 rounded-xl text-sm font-mono font-bold text-gray-600 cursor-pointer hover:bg-primary hover:text-white transition-all group/ip shadow-sm border border-gray-100"
                          phx-click={device.ip && JS.dispatch("phx:copy", detail: %{text: device.ip})}
                        >
                          {device.ip || "?.?.?.?"}
                          <.icon
                            :if={device.ip}
                            name="hero-clipboard"
                            class="w-4 h-4 opacity-50 group-hover/ip:opacity-100"
                          />
                        </div>
                      </td>
                      <td class="px-8 py-6">
                        <div class="text-gray-900 font-bold">
                          {device.product || "Unknown Product"}
                        </div>
                        <div class="flex items-center gap-2 mt-1">
                          <span class="text-xs font-medium px-2 py-0.5 bg-gray-100 text-gray-500 rounded-md">
                            Version
                          </span>
                          <span class="text-xs text-gray-400 font-mono">
                            {device.version || "---"}
                          </span>
                        </div>
                      </td>
                      <td class="px-8 py-6 text-right">
                        <.link
                          navigate={
                            ~p"/console?ip=#{device.ip}&name=#{device.name || device.hostname}"
                          }
                          class="btn btn-sm btn-ghost text-primary hover:bg-primary hover:text-white rounded-xl flex items-center gap-2 w-fit ml-auto shadow-sm transition-all"
                        >
                          <.icon name="hero-command-line" class="w-4 h-4" /> Console
                        </.link>
                      </td>
                    </tr>
                  <% end %>
                </tbody>
              </table>
            </div>
          </div>
        <% end %>
      </div>
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
