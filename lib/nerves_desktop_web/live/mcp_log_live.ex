defmodule NervesDesktopWeb.McpLogLive do
  use NervesDesktopWeb, :live_view

  alias NervesDesktop.MCP

  @tail 200_000

  @impl true
  def mount(params, _session, socket) do
    target = params["target"]

    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, MCP.topic())
      if target, do: Phoenix.PubSub.subscribe(NervesDesktop.PubSub, MCP.log_topic(target))
      send(self(), :follow)
    end

    {:ok,
     socket
     |> assign(page_title: "MCP log")
     |> assign(target: target, name: params["name"] || target)
     |> assign(running?: is_map_key(MCP.servers(), target))
     |> assign(path: target && MCP.log_path(target), offset: nil)}
  end

  @impl true
  def handle_info(:follow, socket), do: {:noreply, follow(socket)}

  @impl true
  def handle_info({:mcp_log, _target}, socket), do: {:noreply, follow(socket)}

  @impl true
  def handle_info({:mcp_changed, servers}, socket) do
    {:noreply, assign(socket, running?: is_map_key(servers, socket.assigns.target))}
  end

  # The terminal reports its size and keystrokes, neither of which a log needs.
  @impl true
  def handle_event(_event, _params, socket), do: {:noreply, socket}

  defp follow(%{assigns: %{target: nil}} = socket), do: socket

  defp follow(socket) do
    with path when is_binary(path) <- MCP.log_path(socket.assigns.target),
         {:ok, %{size: size}} <- File.stat(path) do
      socket |> assign(path: path) |> catch_up(path, size)
    else
      _no_log -> socket
    end
  end

  defp catch_up(%{assigns: %{offset: nil}} = socket, path, size) do
    print(socket, path, max(size - @tail, 0), size)
  end

  defp catch_up(%{assigns: %{offset: offset}} = socket, _path, size) when size == offset do
    socket
  end

  # A log that got shorter was started over.
  defp catch_up(%{assigns: %{offset: offset}} = socket, path, size) when size < offset do
    socket |> push_event("clear", %{}) |> print(path, 0, size)
  end

  defp catch_up(socket, path, size), do: print(socket, path, socket.assigns.offset, size)

  defp print(socket, path, from, to) do
    case File.open(path, [:read, :binary], &:file.pread(&1, from, to - from)) do
      {:ok, {:ok, data}} ->
        socket
        |> push_event("print", %{data: Base.encode64(data)})
        |> assign(offset: from + byte_size(data))

      _unreadable ->
        socket
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:devices}>
      <UI.page_header
        title="MCP log"
        subtitle="Everything the board printed while its MCP server ran, agent calls included"
      >
        <:actions>
          <div class="flex items-center gap-3">
            <span :if={@running?} id="mcp-log-live" class="nd-chip nd-chip-live">
              <span class="nd-led"></span> Server running
            </span>
            <span :if={!@running?} class="nd-chip">
              <span class="nd-led opacity-40"></span> Server stopped
            </span>
            <.link navigate={~p"/"} class="nd-btn nd-btn-ghost">
              <.icon name="hero-arrow-left" class="size-4" /> Devices
            </.link>
            <.link
              :if={@target}
              id="mcp-log-open-console"
              navigate={~p"/console?target=#{@target}&name=#{@name}"}
              class="nd-btn nd-btn-secondary"
            >
              <.icon name="hero-command-line" class="size-4" /> Open console
            </.link>
          </div>
        </:actions>
      </UI.page_header>

      <div class="flex min-h-0 flex-1 flex-col">
        <section class="flex flex-1 flex-col overflow-hidden rounded-lg border border-ink bg-ink shadow-panel">
          <div class="flex items-center gap-3 border-b border-white/10 bg-chassis-deep px-4 py-2.5">
            <span class={[
              "size-2 shrink-0 rounded-full transition-colors",
              (@running? && "bg-live shadow-[0_0_7px_0_var(--color-live)] motion-safe:animate-pulse") ||
                "bg-white/25"
            ]}></span>
            <span class="truncate font-mono text-xs text-secondary">{@name || "No device"}</span>
            <span :if={@path} id="mcp-log-path" class="ml-auto min-w-0">
              <UI.copyable value={@path} class="text-white/60" />
            </span>
            <span :if={!@path} id="mcp-log-empty" class="ml-auto font-mono text-xs text-white/60">
              Nothing logged yet
            </span>
          </div>

          <div class="flex-1 overflow-hidden p-3">
            <div id="mcp-log-terminal" phx-update="ignore" phx-hook="Xterm" class="h-full w-full">
            </div>
          </div>
        </section>
      </div>
    </Layouts.app>
    """
  end
end
