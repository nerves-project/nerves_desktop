defmodule NervesDesktopWeb.ConsoleLive do
  use NervesDesktopWeb, :live_view

  require Logger
  alias NervesDesktop.Connection
  alias NervesDesktop.ConnectionSupervisor
  alias NervesDesktop.Connections.{ErlangSSH, SystemSSH, UART}

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "discovery")
    end

    {:ok,
     socket
     |> assign(page_title: "Console")
     |> assign(devices: NervesDesktop.DeviceScanner.get_devices())
     |> assign(connection_pid: nil)
     |> assign(connection_module: nil)
     |> assign(status: :disconnected)
     |> assign(selected_target: nil)
     |> assign(subscribed_target: nil)
     |> assign(selected_name: nil)
     |> assign(password: "")
     |> assign(term_size: {80, 24})}
  end

  @impl true
  def handle_params(params, _url, socket) do
    target = params["target"] || params["ip"]
    name = params["name"]

    {target, name} =
      if is_nil(target) do
        case Registry.select(NervesDesktop.ConnectionRegistry, [{{:"$1", :_, :_}, [], [:"$1"]}]) do
          [active_target | _] ->
            device = Enum.find(socket.assigns.devices, &(&1[:target] == active_target))
            active_name = (device && (device[:name] || device[:hostname])) || "Unknown"
            {active_target, active_name}

          [] ->
            {nil, nil}
        end
      else
        {target, name}
      end

    socket =
      if target do
        socket
        |> maybe_clear_terminal(target)
        |> assign(selected_target: target)
        |> assign(selected_name: name)
        |> check_existing_connection(target)
        |> maybe_prompt_connect()
      else
        socket
      end

    {:noreply, socket}
  end

  defp maybe_clear_terminal(socket, new_target) do
    if socket.assigns.selected_target != new_target do
      push_event(socket, "clear", %{})
    else
      socket
    end
  end

  defp maybe_prompt_connect(
         %{assigns: %{status: :disconnected, selected_target: target}} = socket
       )
       when is_binary(target) do
    push_print(
      socket,
      "\r\n\x1B[1;36m#{target}\x1B[0m\r\n\x1B[90mClick Connect to start a session.\x1B[0m\r\n"
    )
  end

  defp maybe_prompt_connect(socket), do: socket

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
        |> push_history(history)

      _ ->
        socket
    end
  end

  defp subscribe_to_target(socket, target) do
    if socket.assigns.subscribed_target != target do
      if socket.assigns.subscribed_target do
        Phoenix.PubSub.unsubscribe(
          NervesDesktop.PubSub,
          "connection_output:#{socket.assigns.subscribed_target}"
        )
      end

      if connected?(socket) do
        Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "connection_output:#{target}")
      end

      assign(socket, subscribed_target: target)
    else
      socket
    end
  end

  defp push_history(socket, history) do
    socket
    |> push_event("clear", %{})
    |> push_print(history)
  end

  defp push_print(socket, data) do
    b64_data = Base.encode64(data)
    push_event(socket, "print", %{data: b64_data})
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, assign(socket, devices: devices)}
  end

  @impl true
  def handle_info({:connection_output, target, data}, socket) do
    if socket.assigns.selected_target == target do
      {:noreply, push_print(socket, data)}
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
    device = Enum.find(socket.assigns.devices, &(&1[:target] == target))

    {:noreply,
     socket
     |> maybe_clear_terminal(target)
     |> assign(selected_target: target)
     |> assign(password: password)
     |> assign(selected_name: device && (device[:name] || device[:hostname]))}
  end

  @impl true
  def handle_event("connect", _params, socket) do
    socket.assigns.selected_target
    |> validate_target()
    |> perform_connection(socket)
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
     |> push_print("\r\n\x1B[1;31mSession disconnected.\x1B[0m\r\n")}
  end

  @impl true
  def handle_event("resize", %{"cols" => cols, "rows" => rows}, socket)
      when is_integer(cols) and is_integer(rows) and cols > 0 and rows > 0 do
    if socket.assigns.connection_pid && socket.assigns.connection_module do
      socket.assigns.connection_module.resize(socket.assigns.connection_pid, cols, rows)
    end

    {:noreply, assign(socket, term_size: {cols, rows})}
  end

  @impl true
  def handle_event("resize", _params, socket), do: {:noreply, socket}

  @impl true
  def handle_event("clear_terminal", _params, socket) do
    {:noreply, push_event(socket, "clear", %{})}
  end

  @impl true
  def handle_event("data", %{"data" => data}, socket) do
    if socket.assigns.connection_pid && socket.assigns.connection_module do
      socket.assigns.connection_module.send_data(socket.assigns.connection_pid, data)
    end

    {:noreply, socket}
  end

  defp backend_name(ErlangSSH), do: "Erlang SSH"
  defp backend_name(SystemSSH), do: "System SSH"
  defp backend_name(UART), do: "Serial"
  defp backend_name(module), do: module |> Module.split() |> List.last()

  defp validate_target(nil), do: {:error, :no_target}
  defp validate_target(""), do: {:error, :no_target}
  defp validate_target(target), do: {:ok, target}

  defp perform_connection({:error, :no_target}, socket) do
    {:noreply, put_flash(socket, :error, "Please select a device first.")}
  end

  defp perform_connection({:ok, target}, socket) do
    device = Enum.find(socket.assigns.devices, &(&1[:target] == target))

    module =
      Connection.backend_for(
        device || %{},
        Application.get_env(:nerves_desktop, :ssh_client, :erlang_ssh),
        :os.type()
      )

    socket =
      socket
      |> push_event("clear", %{})
      |> push_print("\r\n\x1B[1;33mConnecting to #{target} via #{inspect(module)}...\x1B[0m\r\n")

    ConnectionSupervisor.start_child(module, target: target)
    |> handle_connection_result(socket, module, target)
  end

  defp handle_connection_result({:ok, pid}, socket, module, target) do
    socket = subscribe_to_target(socket, target)

    password = if(socket.assigns.password == "", do: nil, else: socket.assigns.password)

    {cols, rows} = socket.assigns.term_size
    module.resize(pid, cols, rows)

    case module.connect(pid, target, "root", password) do
      :ok ->
        socket =
          assign(socket, status: :connected, connection_pid: pid, connection_module: module)

        {:noreply, socket}

      {:error, reason} ->
        ConnectionSupervisor.stop_child(pid)
        socket = put_flash(socket, :error, "Connection failed: #{format_error(reason)}")
        {:noreply, socket}
    end
  end

  defp handle_connection_result({:error, {:already_started, pid}}, socket, module, target) do
    socket = subscribe_to_target(socket, target)

    module =
      case Registry.lookup(NervesDesktop.ConnectionRegistry, target) do
        [{_, m}] -> m
        _ -> module
      end

    history = apply(module, :get_history, [pid])

    socket =
      socket
      |> assign(status: :connected, connection_pid: pid, connection_module: module)
      |> push_history(history)

    {:noreply, socket}
  end

  defp handle_connection_result({:error, reason}, socket, _module, _target) do
    socket = put_flash(socket, :error, "Failed to start connection: #{format_error(reason)}")
    {:noreply, socket}
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:console}>
      <UI.page_header title="Console" subtitle="A live shell on the board, over SSH or serial">
        <:actions>
          <span :if={@status == :connected} class="nd-chip nd-chip-live">
            <span class="nd-led"></span> Session open
          </span>
          <span :if={@status != :connected} class="nd-chip">
            <span class="nd-led opacity-40"></span> No session
          </span>
        </:actions>
      </UI.page_header>

      <UI.panel label="Open a session" body_class="p-4">
        <UI.ssh_connection_form
          devices={@devices}
          selected_target={@selected_target}
          password={@password}
          status={@status}
        />

        <div
          :if={@status == :connected && @connection_module != UART}
          class="nd-note nd-note-caution mt-4"
        >
          <.icon name="hero-shield-exclamation" class="mt-px size-4 shrink-0 text-caution" />
          <span>
            This session skips host key verification, so it cannot tell you if something
            else answered instead of your board. Use it on networks you control.
          </span>
        </div>

        <div
          :if={@status == :connected && @connection_module == SystemSSH}
          class="nd-note nd-note-info mt-3"
        >
          <.icon name="hero-information-circle" class="mt-px size-4 shrink-0 text-primary" />
          <span>
            System SSH holds the terminal at 80&times;24 no matter how large this window
            gets. Switch to Erlang SSH in
            <.link navigate={~p"/settings"} class="font-semibold text-primary underline">
              Settings
            </.link>
            for a console that follows the window.
          </span>
        </div>
      </UI.panel>

      <div class="flex min-h-0 flex-1 flex-col">
        <section class="flex flex-1 flex-col overflow-hidden rounded-lg border border-ink bg-ink shadow-panel">
          <div class="flex items-center gap-3 border-b border-white/10 bg-chassis-deep px-4 py-2.5">
            <span class={[
              "size-2 shrink-0 rounded-full transition-colors",
              (@status == :connected &&
                 "bg-live shadow-[0_0_7px_0_var(--color-live)] motion-safe:animate-pulse") ||
                "bg-white/25"
            ]}>
            </span>
            <span class={[
              "truncate font-mono text-xs",
              (@selected_target && "text-secondary") || "text-white/60"
            ]}>
              {@selected_name || "Nothing selected"}
            </span>
            <span :if={@selected_target} class="truncate font-mono text-xs text-white/60">
              {@selected_target}
            </span>

            <span class="ml-auto flex shrink-0 items-center gap-3">
              <span
                :if={@connection_module}
                class="font-mono text-2xs tracking-wider text-white/60 uppercase"
              >
                {backend_name(@connection_module)}
              </span>
              <button
                type="button"
                id="clear-terminal"
                phx-click="clear_terminal"
                class="rounded-sm px-2 py-1 font-mono text-2xs tracking-wider text-white/70 uppercase transition-colors hover:bg-white/10 hover:text-white"
              >
                Clear
              </button>
            </span>
          </div>

          <div class="flex-1 overflow-hidden p-3">
            <div id="terminal" phx-update="ignore" phx-hook="Xterm" class="h-full w-full"></div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
