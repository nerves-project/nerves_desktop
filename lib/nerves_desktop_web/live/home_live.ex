defmodule NervesDesktopWeb.HomeLive do
  use NervesDesktopWeb, :live_view

  alias NervesDesktop.Firmware.Catalog
  alias NervesDesktop.Firmware.ReleaseIndex
  alias NervesDesktop.Firmware.UpdateSession
  alias NervesDesktop.Firmware.UpdateSupervisor
  alias NervesDesktop.Connections.SSHError
  alias NervesDesktop.MCP
  alias NervesDesktop.Native

  @impl true
  def mount(_params, _session, socket) do
    devices = NervesDesktop.DeviceScanner.get_devices()

    if connected?(socket) do
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "discovery")
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "releases")
      Phoenix.PubSub.subscribe(NervesDesktop.PubSub, MCP.topic())
      Native.subscribe("file_dialog_result")
      # An upload outlives this page, so pick up any already in flight.
      Enum.each(Map.keys(UpdateSession.active()), &subscribe_to_updates/1)
    end

    {:ok,
     socket
     |> assign(page_title: "Devices")
     |> assign(mdns_snippet: mount_snippet())
     |> assign(mdns_html: NervesDesktopWeb.ElixirSnippet.to_html(mount_snippet()))
     |> assign(last_scan_at: DateTime.utc_now())
     |> assign(open_menu: nil)
     |> assign(native?: Native.available?())
     |> assign(updates: UpdateSession.active())
     |> assign(update_sources: %{})
     |> assign(show_all?: false)
     |> assign(mcp: MCP.servers())
     |> put_devices(devices)}
  end

  @impl true
  def handle_info({:devices_updated, devices}, socket) do
    {:noreply, socket |> assign(last_scan_at: DateTime.utc_now()) |> put_devices(devices)}
  end

  @impl true
  def handle_info({:release_resolved, _key}, socket) do
    {:noreply, put_devices(socket, socket.assigns.devices)}
  end

  @impl true
  def handle_info({:update_progress, device_id, progress}, socket) do
    if progress.phase == :rebooting do
      Process.send_after(self(), {:forget_update, device_id}, :timer.minutes(3))
    end

    {:noreply, assign(socket, updates: Map.put(socket.assigns.updates, device_id, progress))}
  end

  @impl true
  def handle_info({:forget_update, device_id}, socket) do
    case socket.assigns.updates[device_id] do
      %{phase: :rebooting} ->
        {:noreply, assign(socket, updates: Map.delete(socket.assigns.updates, device_id))}

      _ ->
        {:noreply, socket}
    end
  end

  @impl true
  def handle_info({:mcp_changed, servers}, socket) do
    {:noreply, assign(socket, mcp: servers)}
  end

  # The Tauri file dialog answers with the chosen path.
  @impl true
  def handle_info(path, socket) when is_binary(path) do
    case socket.assigns[:awaiting_file] do
      nil ->
        {:noreply, socket}

      device ->
        {:noreply,
         socket
         |> assign(awaiting_file: nil)
         |> start_update(device, {:file, path})}
    end
  end

  @impl true
  def handle_event("scan_now", _params, socket) do
    NervesDesktop.DeviceScanner.scan_now()
    {:noreply, socket}
  end

  @impl true
  def handle_event("toggle_show_all", _params, socket) do
    {:noreply, socket |> update(:show_all?, &(!&1)) |> assign_groups()}
  end

  @impl true
  def handle_event("toggle_menu", %{"id" => id}, socket) do
    open = if socket.assigns.open_menu == id, do: nil, else: id
    {:noreply, assign(socket, open_menu: open)}
  end

  @impl true
  def handle_event("close_menu", _params, socket) do
    {:noreply, assign(socket, open_menu: nil)}
  end

  @impl true
  def handle_event("update_from_catalog", %{"id" => id}, socket) do
    device = find_device(socket, id)

    case device && Catalog.match(device) do
      {:ok, name, config} ->
        {:noreply,
         socket
         |> assign(open_menu: nil)
         |> start_update(device, {:catalog, name, config, device[:platform]})}

      _ ->
        {:noreply, assign(socket, open_menu: nil)}
    end
  end

  @impl true
  def handle_event("update_from_file", %{"id" => id}, socket) do
    device = find_device(socket, id)

    Native.broadcast("messages", "open_file_dialog")

    {:noreply, socket |> assign(open_menu: nil) |> assign(awaiting_file: device)}
  end

  @impl true
  def handle_event("start_mcp", %{"id" => id}, socket) do
    socket = assign(socket, open_menu: nil)

    with %{} = device <- find_device(socket, id),
         {:error, reason} <- MCP.start_server(device) do
      {:noreply, put_flash(socket, :error, "Could not start the MCP server: #{inspect(reason)}")}
    else
      _ -> {:noreply, socket}
    end
  end

  @impl true
  def handle_event("stop_mcp", %{"id" => id}, socket) do
    if device = find_device(socket, id), do: MCP.stop_server(device[:target])
    {:noreply, assign(socket, open_menu: nil)}
  end

  @impl true
  def handle_event("retry_update", %{"id" => id, "retry" => %{"password" => password}}, socket) do
    case socket.assigns.update_sources[id] do
      nil ->
        {:noreply, socket}

      {source, device} ->
        password = if password == "", do: nil, else: password

        {:noreply,
         socket
         |> assign(updates: Map.delete(socket.assigns.updates, id))
         |> start_update(device, source, password: password)}
    end
  end

  @impl true
  def handle_event("cancel_update", %{"id" => id}, socket) do
    UpdateSupervisor.cancel(id)
    {:noreply, assign(socket, updates: Map.delete(socket.assigns.updates, id))}
  end

  defp find_device(socket, id), do: Enum.find(socket.assigns.devices, &(&1[:id] == id))

  defp subscribe_to_updates(device_id) do
    Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "update:#{device_id}")
  end

  defp put_devices(socket, devices) do
    socket
    |> assign(devices: devices)
    |> assign_groups()
    |> assign(firmware_status: ReleaseIndex.statuses(devices))
    |> retire_finished_updates(devices)
  end

  defp assign_groups(socket) do
    {other, nerves} = Enum.split_with(socket.assigns.devices, &NervesDesktop.Device.unknown?/1)
    visible = if socket.assigns.show_all?, do: nerves ++ other, else: nerves

    assign(socket,
      nerves_devices: nerves,
      other_devices: other,
      visible_devices: visible,
      newest_arrival_at: newest_arrival_at(nerves)
    )
  end

  # A rebooting device drops off the network and comes back. Watching for that
  # round trip is what tells us the update landed: a reinstall keeps the same
  # firmware uuid, so comparing versions would never notice.
  defp retire_finished_updates(socket, devices) do
    present = MapSet.new(devices, & &1[:id])

    updates =
      socket.assigns.updates
      |> Enum.flat_map(fn
        {id, %{phase: :rebooting} = progress} ->
          cond do
            not MapSet.member?(present, id) -> [{id, Map.put(progress, :left, true)}]
            Map.get(progress, :left) -> []
            true -> [{id, progress}]
          end

        entry ->
          [entry]
      end)
      |> Map.new()

    assign(socket, updates: updates)
  end

  defp start_update(socket, device, source, opts \\ []) do
    subscribe_to_updates(device[:id])

    socket = update(socket, :update_sources, &Map.put(&1, device[:id], {source, device}))

    case UpdateSupervisor.start_update(device, source, opts) do
      {:ok, _pid} ->
        assign(socket,
          updates:
            Map.put(socket.assigns.updates, device[:id], %{
              phase: :starting,
              percent: nil,
              error: nil
            })
        )

      {:error, :already_running} ->
        put_flash(socket, :error, "An update is already running for #{device[:name]}.")

      {:error, reason} ->
        put_flash(socket, :error, "Could not start the update: #{inspect(reason)}")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:devices}>
      <UI.page_header
        title="Devices"
        subtitle={device_summary(@nerves_devices)}
      >
        <:actions>
          <UI.scanning_status last_scan_at={@last_scan_at} on_refresh="scan_now" />
        </:actions>
      </UI.page_header>

      <%= if @visible_devices == [] do %>
        <UI.panel body_class="p-0">
          <div class="flex flex-col items-center px-6 py-10 text-center">
            <.icon name="hero-cpu-chip" class="size-9 text-rule-strong" />
            <%= if @other_devices == [] do %>
              <h2 class="mt-3 font-display text-lg font-semibold">No devices found</h2>
              <p class="mt-1.5 max-w-md text-[13px] leading-relaxed text-muted">
                Nothing has responded on your network or on a serial port. Scanning keeps
                running, so a device will appear here as soon as it answers.
              </p>
            <% else %>
              <h2 class="mt-3 font-display text-lg font-semibold">No Nerves devices found</h2>
              <p class="mt-1.5 max-w-md text-[13px] leading-relaxed text-muted">
                Other devices on your network answered, but none of them look like a Nerves
                device. If yours uses a custom hostname, it is among them.
              </p>
              <.unknown_toggle
                count={length(@other_devices)}
                expanded={@show_all?}
                class="nd-btn-secondary mt-4"
              />
            <% end %>
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
                <dt class="text-[13px] font-semibold">Hostname</dt>
                <dd class="text-[13px] leading-relaxed text-muted">
                  A device is recognised as Nerves when its hostname starts with
                  <UI.code text="nerves-" /> or it advertises the
                  <UI.code text="_nerves-device._tcp" />
                  mDNS service. Anything else is listed as unknown.
                </dd>
              </div>
              <div class="grid grid-cols-[7.5rem_1fr] gap-4 py-3">
                <dt class="text-[13px] font-semibold">No network</dt>
                <dd class="text-[13px] leading-relaxed text-muted">
                  Connect the device over USB instead. Nerves devices are configured as USB
                  ethernet gadget by default, and will connect to your computer directly.
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
                  <th class="nd-label px-4 py-2">Found</th>
                  <th class="nd-label px-4 py-2">
                    <span class="sr-only">Update progress</span>
                  </th>
                  <th class="nd-label px-4 py-2 text-right">
                    <span class="sr-only">Actions</span>
                  </th>
                </tr>
              </thead>
              <tbody id="nerves-devices" class="divide-y divide-rule">
                <.device_row
                  :for={device <- @nerves_devices}
                  device={device}
                  status={@firmware_status[device[:id]]}
                  progress={@updates[device[:id]]}
                  menu_open={@open_menu == device[:id]}
                  native={@native?}
                  new={newest_arrival?(device, @newest_arrival_at)}
                  now={@last_scan_at}
                  mcp={@mcp[device[:target]]}
                />
              </tbody>
              <tbody
                :if={@show_all? and @other_devices != []}
                id="unknown-devices"
                class="divide-y divide-rule border-t border-rule"
              >
                <tr>
                  <td colspan="6" class="nd-label bg-sunk px-4 py-1.5">Unknown devices</td>
                </tr>
                <.device_row
                  :for={device <- @other_devices}
                  device={device}
                  status={@firmware_status[device[:id]]}
                  progress={@updates[device[:id]]}
                  menu_open={@open_menu == device[:id]}
                  native={@native?}
                  new={newest_arrival?(device, @newest_arrival_at)}
                  now={@last_scan_at}
                  mcp={@mcp[device[:target]]}
                />
              </tbody>
            </table>
          </div>

          <div :if={@other_devices != []} class="border-t border-rule px-3 py-2">
            <.unknown_toggle count={length(@other_devices)} expanded={@show_all?} />
          </div>
        </UI.panel>
      <% end %>

      <UI.panel
        :if={any_details_missing?(@visible_devices)}
        label="Some devices aren't reporting firmware details"
        body_class="p-5"
      >
        <:actions>
          <button
            phx-click={JS.dispatch("phx:copy", detail: %{text: @mdns_snippet})}
            class="nd-btn nd-btn-ghost h-7"
          >
            <.icon name="hero-clipboard" class="size-3.5" /> Copy
          </button>
        </:actions>

        <p class="max-w-3xl text-[13px] leading-relaxed text-muted">
          A device only advertises what it is told to. Add this to
          <UI.code text="Application.start/2" /> on the device to fill in the blank columns.
        </p>

        <pre class="nd-well nd-code mt-4 overflow-x-auto p-4"><code>{@mdns_html}</code></pre>
      </UI.panel>
    </Layouts.app>
    """
  end

  defp log_path(device) do
    ~p"/mcp/log?target=#{device[:target]}&name=#{device[:name] || device[:hostname] || device[:target]}"
  end

  attr :device, :map, required: true
  attr :url, :string, required: true

  # Hovering the address offers the command that adds it to an agent, named
  # after the device so several of them stay tellable apart in the client.
  defp mcp_address(assigns) do
    assigns = assign(assigns, name: MCP.client_name(assigns.device))

    ~H"""
    <div id={"mcp-copy-#{@device[:id]}"} phx-hook="HoverPanel">
      <UI.copyable value={@url} />
      <div data-panel role="menu" class="nd-menu" hidden>
        <button
          type="button"
          role="menuitem"
          id={"mcp-copy-url-#{@device[:id]}"}
          phx-click={JS.dispatch("phx:copy", detail: %{text: @url})}
          title={@url}
          class="nd-menu-item"
        >
          <.icon name="hero-clipboard" class="size-4" /> Copy URL
        </button>
        <button
          :for={{agent, label} <- [claude_code: "Claude Code", codex: "Codex"]}
          type="button"
          role="menuitem"
          id={"mcp-copy-#{agent}-#{@device[:id]}"}
          phx-click={JS.dispatch("phx:copy", detail: %{text: MCP.add_command(agent, @name, @url)})}
          title={MCP.add_command(agent, @name, @url)}
          class="nd-menu-item"
        >
          <.icon name="hero-clipboard" class="size-4" /> Copy for {label}
        </button>
      </div>
    </div>
    """
  end

  attr :device, :map, required: true
  attr :status, :any, default: nil
  attr :progress, :map, default: nil
  attr :menu_open, :boolean, default: false
  attr :native, :boolean, default: false
  attr :new, :boolean, default: false
  attr :now, DateTime, required: true
  attr :mcp, :map, default: nil

  defp device_row(assigns) do
    ~H"""
    <tr data-new-device={@new} class="group transition-colors hover:bg-sunk">
      <td class="px-4 py-3">
        <div class="flex items-center gap-2">
          <span class="font-semibold">{@device[:name]}</span>
          <span :if={@new} class="nd-chip nd-chip-live">
            <span class="nd-led"></span> New
          </span>
        </div>
        <UI.copyable value={@device[:hostname]} class="mt-0.5" />
      </td>
      <td class="px-4 py-3">
        <div class="flex items-center gap-2">
          <span class={[
            "nd-chip",
            (@device[:type] == :uart && "nd-chip-serial") || "nd-chip-signal"
          ]}>
            <span class="nd-led"></span>
            {if @device[:type] == :uart, do: "Serial", else: "Network"}
          </span>
          <UI.copyable value={@device[:ip] || @device[:target]} />
        </div>
        <div :if={@mcp} id={"mcp-#{@device[:id]}"} class="mt-1.5 flex items-center gap-2">
          <span class="nd-chip nd-chip-live">
            <span class="nd-led"></span> MCP
          </span>
          <.mcp_address device={@device} url={@mcp.url} />
        </div>
      </td>
      <td class="px-4 py-3">
        <div class="flex items-center gap-2">
          <span class="text-[13px] font-semibold">{@device[:product] || "Unknown"}</span>
          <span
            :if={match?({:stale, _}, @status)}
            class="nd-chip nd-chip-caution"
          >
            {elem(@status, 1)} available
          </span>
        </div>
        <div class="mt-0.5 flex items-center gap-1.5 font-mono text-xs whitespace-nowrap text-muted">
          <span>{@device[:version] || "no version"}</span>
          <span :if={@device[:platform]} class="text-rule-strong">/</span>
          <span :if={@device[:platform]}>{@device[:platform]}</span>
        </div>
      </td>
      <td class="px-4 py-3">
        <.found_at :if={@device[:first_seen_at]} device={@device} now={@now} />
      </td>
      <td class="px-4 py-3">
        <div :if={@progress} class="min-w-48">
          <.update_progress
            progress={@progress}
            id={@device[:id]}
            target={@device[:name] || @device[:target]}
          />
        </div>
      </td>
      <td class="px-4 py-3">
        <div class="flex items-center justify-end gap-1.5">
          <.link
            :if={@mcp}
            id={"mcp-log-#{@device[:id]}"}
            navigate={log_path(@device)}
            class="nd-btn nd-btn-ghost"
          >
            <.icon name="hero-document-text" class="size-4" /> Log
          </.link>
          <.link
            navigate={
              ~p"/console?target=#{@device[:target]}&name=#{@device[:name] || @device[:hostname]}"
            }
            class="nd-btn nd-btn-secondary group-hover:border-primary"
          >
            <.icon name="hero-command-line" class="size-4" /> Open console
          </.link>

          <UI.menu id={@device[:id]} open={@menu_open} label={"Actions for #{@device[:name]}"}>
            <.catalog_item :if={@device[:type] == :network} device={@device} status={@status} />
            <button
              :if={@device[:type] == :network}
              type="button"
              role="menuitem"
              phx-click="update_from_file"
              phx-value-id={@device[:id]}
              disabled={!@native}
              title={!@native && "Choosing a file needs the desktop app"}
              class="nd-menu-item"
            >
              <.icon name="hero-document-arrow-up" class="size-4" /> Update from file…
            </button>
            <button
              type="button"
              role="menuitem"
              id={"mcp-toggle-#{@device[:id]}"}
              phx-click={if(@mcp, do: "stop_mcp", else: "start_mcp")}
              phx-value-id={@device[:id]}
              class="nd-menu-item"
            >
              <.icon name="hero-server-stack" class="size-4" />
              {if(@mcp, do: "Stop MCP server", else: "Start MCP server")}
            </button>
            <.link
              :if={!@mcp && MCP.log_path(@device[:target])}
              role="menuitem"
              id={"mcp-last-log-#{@device[:id]}"}
              navigate={log_path(@device)}
              class="nd-menu-item"
            >
              <.icon name="hero-document-text" class="size-4" /> View last MCP log
            </.link>
          </UI.menu>
        </div>
      </td>
    </tr>
    """
  end

  attr :count, :integer, required: true
  attr :expanded, :boolean, default: false
  attr :class, :any, default: "nd-btn-ghost h-7 text-xs"

  defp unknown_toggle(assigns) do
    ~H"""
    <button
      id="toggle-unknown-devices"
      type="button"
      phx-click="toggle_show_all"
      aria-expanded={to_string(@expanded)}
      class={["nd-btn", @class]}
    >
      <.icon
        name="hero-chevron-down"
        class={["size-3.5 transition-transform duration-200", @expanded && "rotate-180"]}
      />
      {toggle_label(@expanded, @count)}
    </button>
    """
  end

  defp toggle_label(true, _count), do: "Hide unknown devices"
  defp toggle_label(false, 1), do: "Show all (1 unknown device)"
  defp toggle_label(false, count), do: "Show all (#{count} unknown devices)"

  attr :device, :map, required: true
  attr :status, :any, default: nil

  # The label has to say what pressing it will do: offering "Update to 0.16.2"
  # on a device already running 0.16.2 reads like a bug rather than a reinstall.
  defp catalog_item(assigns) do
    ~H"""
    <button
      :if={Catalog.updatable?(@device) and catalog_label(@status)}
      type="button"
      role="menuitem"
      phx-click="update_from_catalog"
      phx-value-id={@device[:id]}
      disabled={@status == :pending}
      class="nd-menu-item"
    >
      <.icon name="hero-arrow-down-tray" class="size-4" /> {catalog_label(@status)}
    </button>
    """
  end

  defp catalog_label(:pending), do: "Checking for updates…"
  defp catalog_label({:stale, version}), do: "Update to #{version}"
  defp catalog_label(:current), do: "Reinstall current firmware"
  defp catalog_label(_), do: nil

  attr :progress, :map, required: true
  attr :id, :string, required: true
  attr :target, :string, default: "the device"

  defp update_progress(assigns) do
    ~H"""
    <div :if={@progress.phase == :failed} class="space-y-1.5">
      <div class="flex items-start gap-1.5 text-xs text-danger">
        <.icon name="hero-exclamation-triangle" class="mt-px size-3.5 shrink-0" />
        <span>{format_error(@progress.error, @target)}</span>
      </div>

      <.form
        :let={f}
        :if={SSHError.auth_failure?(@progress.error)}
        for={to_form(%{}, as: :retry)}
        id={"retry-#{@id}"}
        phx-submit="retry_update"
        phx-value-id={@id}
        class="flex items-center gap-1.5"
      >
        <div class="flex-1">
          <.input
            field={f[:password]}
            type="password"
            placeholder="Device password"
            autocomplete="off"
            class="nd-control h-7 text-xs"
          />
        </div>
        <button type="submit" class="nd-btn nd-btn-secondary h-7 px-2 text-xs">Retry</button>
      </.form>
    </div>

    <div :if={@progress.phase != :failed}>
      <div class="mb-1 flex items-baseline justify-between gap-2">
        <span class="text-xs font-medium">{phase_label(@progress.phase)}</span>
        <button
          :if={@progress.phase != :rebooting}
          type="button"
          phx-click="cancel_update"
          phx-value-id={@id}
          class="text-xs text-muted hover:text-danger"
        >
          Cancel
        </button>
      </div>

      <div
        class="h-1.5 overflow-hidden rounded-full bg-rule"
        role="progressbar"
        aria-valuenow={@progress.percent}
        aria-valuemin="0"
        aria-valuemax="100"
      >
        <div
          class={[
            "h-full rounded-full bg-secondary transition-[width] duration-500",
            is_nil(@progress.percent) && "w-1/3 motion-safe:animate-pulse"
          ]}
          style={@progress.percent && "width: #{@progress.percent}%"}
        >
        </div>
      </div>
    </div>
    """
  end

  defp phase_label(:starting), do: "Starting…"
  defp phase_label(:downloading), do: "Downloading"
  defp phase_label(:uploading), do: "Uploading"
  defp phase_label(:rebooting), do: "Sent, rebooting"
  defp phase_label(other), do: to_string(other)

  defp format_error(:no_fwup_subsystem, target),
    do: "#{target} has no fwup SSH subsystem, so it cannot be updated over the air."

  defp format_error({:exit_status, status}, target),
    do: "#{target} rejected the firmware (exit #{status})."

  defp format_error(:timeout, target), do: "#{target} stopped responding."

  # Anything else came from SSH, which already explains what to do next.
  defp format_error(reason, target),
    do: SSHError.describe(reason, target: target, password?: false)

  # Blank Firmware columns mean the device is not advertising its metadata, which
  # is what the mDNS snippet below the table fixes.
  defp any_details_missing?(devices) do
    Enum.any?(devices, fn device ->
      is_nil(device[:product]) or is_nil(device[:version]) or is_nil(device[:platform])
    end)
  end

  attr :device, :map, required: true
  attr :now, DateTime, required: true

  defp found_at(assigns) do
    ~H"""
    <div class={[
      "text-[13px] whitespace-nowrap",
      if(@device[:found_at_launch?], do: "text-muted", else: "font-semibold")
    ]}>
      {found_label(@device, @now)}
    </div>
    <time
      id={"found-#{@device[:id]}"}
      datetime={DateTime.to_iso8601(@device[:first_seen_at])}
      phx-hook="LocalTime"
      class="mt-0.5 block font-mono text-xs tabular-nums text-muted"
    >
      {Calendar.strftime(@device[:first_seen_at], "%H:%M:%S")}
    </time>
    """
  end

  defp found_label(%{found_at_launch?: true}, _now), do: "At launch"

  defp found_label(device, now) do
    case DateTime.diff(now, device.first_seen_at, :minute) do
      minutes when minutes < 1 -> "Just now"
      minutes when minutes < 60 -> "#{minutes} min ago"
      minutes -> "#{div(minutes, 60)} h ago"
    end
  end

  # Devices that arrive in the same scan share a timestamp, so they are all new.
  defp newest_arrival_at(devices) do
    devices
    |> Enum.filter(&(&1[:found_at_launch?] == false))
    |> Enum.map(& &1.first_seen_at)
    |> Enum.max(DateTime, fn -> nil end)
  end

  defp newest_arrival?(_device, nil), do: false
  defp newest_arrival?(device, newest), do: device[:first_seen_at] == newest

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
