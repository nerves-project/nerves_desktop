defmodule NervesDesktopWeb.ConsoleLive do
  use NervesDesktopWeb, :live_view

  require Logger
  alias NervesDesktop.ConnectionSupervisor
  alias NervesDesktop.Connections.{SystemSSH, ErlangSSH, UART}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "discovery")
    end

    {:ok,
     socket
     |> assign(devices: NervesDesktop.DeviceScanner.get_devices())
     |> assign(connection_pid: nil)
     |> assign(connection_module: nil)
     |> assign(status: :disconnected)
     |> assign(selected_target: nil)
     |> assign(subscribed_target: nil)
     |> assign(selected_name: nil)
     |> assign(password: "")}
  end

  @impl true
  def terminate(_reason, socket) do
    if socket.assigns.subscribed_target do
      Phoenix.PubSub.unsubscribe(NervesDesktop.PubSub, "connection_output:#{socket.assigns.subscribed_target}")
    end
    :ok
  end

  @impl true
  def handle_params(params, _url, socket) do
    target = params["target"] || params["ip"]
    name = params["name"]

    socket =
      if target do
        socket
        |> assign(selected_target: target)
        |> assign(selected_name: name)
        |> check_existing_connection(target)
      else
        socket
      end

    {:noreply, socket}
  end

  defp check_existing_connection(socket, target) do
    case Registry.lookup(NervesDesktop.ConnectionRegistry, target) do
      [{pid, module}] when is_atom(module) ->
        Logger.info("Found existing connection for #{target} using #{inspect(module)}")
        
        socket = subscribe_to_target(socket, target)
        history = apply(module, :get_history, [pid])

        socket
        |> assign(connection_pid: pid)
        |> assign(connection_module: module)
        |> assign(status: :connected)
        |> push_event("print", %{data: history})

      _ ->
        socket
    end
  end

  defp subscribe_to_target(socket, target) do
    if socket.assigns.subscribed_target != target do
      if socket.assigns.subscribed_target do
        Phoenix.PubSub.unsubscribe(NervesDesktop.PubSub, "connection_output:#{socket.assigns.subscribed_target}")
      end
      
      if connected?(socket) do
        Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "connection_output:#{target}")
      end
      
      assign(socket, subscribed_target: target)
    else
      socket
    end
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, assign(socket, devices: devices)}
  end

  @impl true
  def handle_info({:connection_output, target, data}, socket) do
    if socket.assigns.selected_target == target do
      {:noreply, push_event(socket, "print", %{data: data})}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:connection_closed, target}, socket) do
    if socket.assigns.selected_target == target do
      {:noreply,
       socket
       |> assign(status: :disconnected)
       |> assign(connection_pid: nil)
       |> assign(connection_module: nil)
       |> put_flash(:error, "Connection closed.")}
    else
      {:noreply, socket}
    end
  end

  @impl true
  def handle_event(
        "validate_connection",
        %{"connection" => %{"target" => target, "password" => password}},
        socket
      ) do
    device = Enum.find(socket.assigns.devices, &(&1.target == target))

    {:noreply,
     socket
     |> assign(selected_target: target)
     |> assign(password: password)
     |> assign(selected_name: device && (device[:name] || device[:hostname]))}
  end

  @impl true
  def handle_event("connect", _params, socket) do
    target = socket.assigns.selected_target

    if target in [nil, ""] do
      {:noreply, put_flash(socket, :error, "Please select a device first.")}
    else
      device = Enum.find(socket.assigns.devices, &(&1.target == target))
      type = (device && device[:type]) || :network
      
      module = 
        if type == :uart do
          UART
        else
          case Application.get_env(:nerves_desktop, :ssh_client, :system_ssh) do
            :system_ssh -> SystemSSH
            :erlang_ssh -> ErlangSSH
          end
        end

      push_event(socket, "print", %{
        data: "\r\n\x1B[1;33mConnecting to #{target} via #{inspect(module)}...\x1B[0m\r\n"
      })

      # Start child if not already running
      case ConnectionSupervisor.start_child(module, [target: target]) do
        {:ok, pid} ->
          socket = subscribe_to_target(socket, target)

          module.connect(
            pid,
            target,
            "root",
            if(socket.assigns.password == "", do: nil, else: socket.assigns.password)
          )

          {:noreply, assign(socket, status: :connected, connection_pid: pid, connection_module: module)}

        {:error, {:already_started, pid}} ->
          # Already running, just bind
          socket = subscribe_to_target(socket, target)
          
          # Re-fetch module from Registry to be sure
          module = case Registry.lookup(NervesDesktop.ConnectionRegistry, target) do
            [{_, m}] -> m
            _ -> module
          end

          history = apply(module, :get_history, [pid])
          
          {:noreply, 
           socket 
           |> assign(status: :connected, connection_pid: pid, connection_module: module)
           |> push_event("print", %{data: history})}

        {:error, reason} ->
          {:noreply, put_flash(socket, :error, "Failed to start connection: #{inspect(reason)}")}
      end
    end
  end

  @impl true
  def handle_event("disconnect", _params, socket) do
    if socket.assigns.connection_pid do
      ConnectionSupervisor.stop_child(socket.assigns.connection_pid)
    end

    {:noreply,
     socket
     |> assign(status: :disconnected)
     |> assign(connection_pid: nil)
     |> assign(connection_module: nil)
     |> push_event("print", %{data: "\r\n\x1B[1;31mSession disconnected.\x1B[0m\r\n"})}
  end

  @impl true
  def handle_event("data", %{"data" => data}, socket) do
    if socket.assigns.connection_pid && socket.assigns.connection_module do
      socket.assigns.connection_module.send_data(socket.assigns.connection_pid, data)
    end
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:console}>
      <UI.page_header
        icon="hero-command-line"
        title="Device Console"
        subtitle="Interactive terminal via SSH or UART"
      >
        <:actions>
          <UI.ssh_connection_form
            devices={@devices}
            selected_target={@selected_target}
            password={@password}
            status={@status}
          />
        </:actions>
      </UI.page_header>
      
      <div :if={@status == :connected && @connection_module != UART} class="mb-4 flex items-center gap-2 p-3 bg-yellow-50 border border-yellow-100 rounded-xl text-yellow-800 text-xs">
        <.icon name="hero-exclamation-triangle" class="w-4 h-4 text-yellow-600" />
        <span>Host key verification is disabled for this session. Connect only to trusted devices on secure networks.</span>
      </div>

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
                {@selected_name || "no-session"} — {@selected_target || "localhost"}
              </div>
            </div>
            <div class="flex items-center gap-3">
              <div
                :if={@status == :connected}
                class="flex items-center gap-2 text-xs text-green-500 font-bold uppercase tracking-widest"
              >
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
              Interactive PTY Mode — {if @connection_module, do: inspect(@connection_module), else: "Not Connected"}
            </div>
            <div class="text-[10px] text-gray-500 font-mono uppercase tracking-widest hidden sm:block">
              UTF-8 / PTY
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
