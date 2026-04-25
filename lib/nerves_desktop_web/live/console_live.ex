defmodule NervesDesktopWeb.ConsoleLive do
  use NervesDesktopWeb, :live_view

  alias NervesDesktop.SSHConnection

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "discovery")
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "ssh_connection")
    end

    {:ok, pid} = SSHConnection.start_link([])

    {:ok,
     socket
     |> assign(devices: NervesDesktop.Discovery.get_devices())
     |> assign(selected_ip: nil)
     |> assign(selected_name: nil)
     |> assign(status: :disconnected)
     |> assign(ssh_pid: pid)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    ip = params["ip"]
    name = params["name"]

    socket =
      if ip do
        socket
        |> assign(selected_ip: ip)
        |> assign(selected_name: name)
        |> then(fn s -> 
          if connected?(s) do
            # Small delay to ensure xterm is ready on the client
            Process.send_after(self(), :auto_connect, 500)
            s
          else
            s
          end
        end)
      else
        socket
      end

    {:noreply, socket}
  end

  @impl true
  def handle_info(:auto_connect, socket) do
    handle_event("connect", %{}, socket)
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, assign(socket, devices: devices)}
  end

  @impl true
  def handle_info({:ssh_output, device_ip, data}, socket) do
    if socket.assigns.selected_ip == device_ip do
      {:noreply, push_event(socket, "print", %{data: data})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event("select_device", %{"ip" => ip}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1.ip == ip))
    {:noreply, assign(socket, selected_ip: ip, selected_name: device && (device.name || device.hostname))}
  end

  @impl true
  def handle_event("connect", _params, %{assigns: %{selected_ip: nil}} = socket) do
    {:noreply, put_flash(socket, :error, "Please select a device first.")}
  end

  @impl true
  def handle_event("connect", _params, socket) do
    push_event(socket, "print", %{data: "\r\n\x1B[1;33mConnecting to #{socket.assigns.selected_ip}...\x1B[0m\r\n"})
    
    SSHConnection.connect(
      socket.assigns.ssh_pid, 
      socket.assigns.selected_ip
    )

    {:noreply, assign(socket, status: :connected)}
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    SSHConnection.disconnect(socket.assigns.ssh_pid)
    {:noreply, 
     socket 
     |> assign(status: :disconnected)
     |> push_event("print", %{data: "\r\n\x1B[1;31mSession disconnected.\x1B[0m\r\n"})}
  end

  @impl true
  def handle_event("data", %{"data" => data}, socket) do
    SSHConnection.send_data(socket.assigns.ssh_pid, data)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:console}>
      <div class="p-4 md:p-8 w-full h-full flex flex-col">
        <header class="flex flex-col md:flex-row justify-between items-start md:items-center gap-6 mb-10">
          <div>
            <h1 class="text-4xl font-extrabold tracking-tight text-gray-900 flex items-center gap-3">
              <div class="p-2 bg-primary/10 rounded-xl text-primary">
                <.icon name="hero-command-line" class="w-10 h-10" />
              </div>
              Device Console
            </h1>
            <p class="text-lg text-gray-500 mt-2 font-medium">
              Interactive terminal via system SSH
            </p>
          </div>

          <div class="flex items-center gap-4 bg-white p-3 rounded-2xl shadow-sm border border-gray-100 w-full md:w-auto">
            <div class="flex flex-col gap-1 flex-1 md:flex-none">
              <label class="text-[10px] uppercase font-bold text-gray-400 px-1">Target Device</label>
              <select
                name="ip"
                phx-change="select_device"
                class="select select-sm select-ghost focus:bg-transparent border-none focus:ring-0 font-bold text-gray-700 min-w-[240px]"
              >

                <option value="">Select a device...</option>
                <%= for device <- @devices do %>
                  <option value={device.ip} selected={device.ip == @selected_ip}>
                    {device.name || device.hostname} ({device.ip})
                  </option>
                <% end %>
              </select>
            </div>

            <div class="h-10 w-px bg-gray-100 hidden sm:block"></div>

            <div class="flex items-center">
              <%= if @status == :disconnected do %>
                <button
                  phx-click="connect"
                  class="btn btn-primary btn-sm rounded-xl shadow-lg shadow-primary/20 flex items-center gap-2 h-10 px-8"
                >
                  <.icon name="hero-bolt" class="w-4 h-4" /> Connect
                </button>
              <% else %>
                <button
                  phx-click="disconnect"
                  class="btn btn-error btn-outline btn-sm rounded-xl flex items-center gap-2 h-10 px-8"
                >
                  <.icon name="hero-x-mark" class="w-4 h-4" /> Disconnect
                </button>
              <% end %>
            </div>
          </div>
        </header>

        <div class="flex-1 flex flex-col min-h-0">
          <div class="bg-gray-900 rounded-[2rem] shadow-2xl overflow-hidden flex flex-col border border-gray-800 h-[600px]">
            <!-- Terminal Header -->
            <div class="bg-gray-800/50 px-6 py-4 flex items-center justify-between border-b border-gray-700/50">
              <div class="flex items-center gap-4">
                <div class="flex gap-2">
                  <div class="w-3 h-3 rounded-full bg-red-500/80"></div>
                  <div class="w-3 h-3 rounded-full bg-yellow-500/80"></div>
                  <div class="w-3 h-3 rounded-full bg-green-500/80"></div>
                </div>
                <div class="h-4 w-px bg-gray-700"></div>
                <div class="text-xs font-mono text-gray-400 flex items-center gap-2">
                  <.icon name="hero-server" class="w-3 h-3" />
                  {@selected_name || "no-session"} — root@{(@selected_ip || "localhost")}
                </div>
              </div>
              <div class="flex items-center gap-3">
                <div :if={@status == :connected} class="flex items-center gap-2 text-xs text-green-500 font-bold uppercase tracking-widest">
                  <span>Online</span>
                  <span class="w-2 h-2 rounded-full bg-green-500 animate-pulse"></span>
                </div>
              </div>
            </div>

            <!-- Terminal Content -->
            <div class="flex-1 p-4 overflow-hidden bg-gray-900">
               <div id="terminal" phx-update="ignore" phx-hook="Xterm" class="h-full w-full"></div>
            </div>

            <!-- Terminal Footer -->
            <div class="bg-gray-800/30 px-6 py-3 border-t border-gray-700/50 flex justify-between items-center">
              <div class="text-[10px] text-gray-500 font-mono uppercase tracking-widest text-ellipsis overflow-hidden whitespace-nowrap">
                Interactive PTY Mode — System SSH
              </div>
              <div class="text-[10px] text-gray-500 font-mono uppercase tracking-widest hidden sm:block">
                UTF-8 / PTY
              </div>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
