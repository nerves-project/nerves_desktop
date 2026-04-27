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
     |> assign(devices: NervesDesktop.DeviceScanner.get_devices())     |> assign(ssh_pid: pid)
     |> assign(status: :disconnected)
     |> assign(selected_ip: nil)
     |> assign(selected_name: nil)
     |> assign(password: "")}
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
  def handle_event("validate_connection", %{"connection" => %{"ip" => ip, "password" => password}}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1.ip == ip))
    {:noreply, 
     socket 
     |> assign(selected_ip: ip)
     |> assign(password: password)
     |> assign(selected_name: device && (device.name || device.hostname))}
  end

  @impl true
  def handle_event("connect", _params, socket) do
    if socket.assigns.selected_ip in [nil, ""] do
      {:noreply, put_flash(socket, :error, "Please select a device first.")}
    else
      push_event(socket, "print", %{data: "\r\n\x1B[1;33mConnecting to #{socket.assigns.selected_ip}...\x1B[0m\r\n"})
      
      SSHConnection.connect(
        socket.assigns.ssh_pid, 
        socket.assigns.selected_ip,
        "root",
        if(socket.assigns.password == "", do: nil, else: socket.assigns.password)
      )

      {:noreply, assign(socket, status: :connected)}
    end
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
        <UI.page_header
          icon="hero-command-line"
          title="Device Console"
          subtitle="Interactive terminal via system SSH"
        >
          <:actions>
            <div class="flex items-center gap-4 bg-white px-8 py-3 rounded-2xl shadow-sm border border-gray-100 w-full md:w-auto">
              <.form
                :let={f}
                for={to_form(%{"ip" => @selected_ip, "password" => @password}, as: :connection)}
                phx-change="validate_connection"
                phx-submit="connect"
                class="flex flex-wrap items-center gap-4"
              >
                <div class="w-fit min-w-[160px]">
                  <.input
                    field={f[:ip]}
                    type="select"
                    label="Target Device"
                    disabled={@status != :disconnected}
                    options={[{"Select a device...", ""} | Enum.map(@devices, &({&1.name || &1.hostname, &1.ip}))]}
                  />
                </div>

                <div class="w-32">
                  <.input
                    field={f[:password]}
                    type="password"
                    label="SSH Password"
                    disabled={@status != :disconnected}
                    placeholder="optional"
                  />
                </div>

                <div class="flex items-center mb-2 mt-6">
                  <%= if @status == :disconnected do %>
                    <button
                      type="submit"
                      class="btn btn-primary btn-md rounded-xl shadow-lg shadow-primary/20 flex items-center gap-2 px-8"
                    >
                      <.icon name="hero-bolt" class="w-4 h-4" /> Connect
                    </button>
                  <% else %>
                    <button
                      type="button"
                      phx-click="disconnect"
                      class="btn btn-error btn-outline btn-md rounded-xl flex items-center gap-2 px-8"
                    >
                      <.icon name="hero-x-mark" class="w-4 h-4" /> Disconnect
                    </button>
                  <% end %>
                </div>
              </.form>
            </div>
          </:actions>
        </UI.page_header>

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
                  <span class="w-2 h-2 rounded-full bg-green-500"></span>
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
