defmodule NervesDesktopWeb.UI do
  use Phoenix.Component
  import NervesDesktopWeb.CoreComponents

  @doc """
  Renders a scanning status indicator with an optional refresh button.
  """
  attr :last_scan_at, :any, required: true
  attr :id, :string, default: "scanning-status"
  attr :on_refresh, :string, default: nil
  attr :class, :string, default: nil

  def scanning_status(assigns) do
    ~H"""
    <div class={[
      "flex items-center gap-4 bg-white px-3 py-2 rounded-2xl shadow-sm border border-gray-100",
      @class
    ]}>
      <div class="flex flex-col items-end">
        <span class="text-[10px] uppercase tracking-wider font-bold text-gray-400">Status</span>
        <div class="flex items-center gap-2">
          <span class="relative flex h-2 w-2">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75">
            </span>
            <span class="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
          </span>
          <span class="text-sm font-semibold text-gray-700">Scanning</span>
        </div>
      </div>
      <div class="h-8 w-px bg-gray-100"></div>
      <div class="flex flex-col items-end">
        <span class="text-[10px] uppercase tracking-wider font-bold text-gray-400">
          Last Scan
        </span>
        <time
          id={@id}
          datetime={DateTime.to_iso8601(@last_scan_at)}
          phx-hook="LocalTime"
          class="text-sm font-mono font-bold text-gray-900"
        >
          {Calendar.strftime(@last_scan_at, "%H:%M:%S")}
        </time>
      </div>

      <%= if @on_refresh do %>
        <button
          phx-click={@on_refresh}
          class="btn btn-primary btn-md shadow-lg shadow-primary/20 flex gap-2 items-center rounded-xl transition-all hover:scale-[1.02] active:scale-[0.98]"
          phx-throttle="2000"
        >
          <.icon name="hero-arrow-path" class="w-5 h-5" /> Refresh
        </button>
      <% end %>
    </div>
    """
  end

  @doc """
  Renders a page header with an icon, title, subtitle, and an actions slot.
  """
  attr :icon, :string, required: true
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class="flex flex-col lg:flex-row justify-between items-start lg:items-center gap-4 mb-10">
      <div>
        <h1 class="text-4xl font-extrabold tracking-tight text-gray-900 flex items-center gap-3">
          <div class="p-2 bg-primary/10 rounded-xl size-12 flex items-center">
            <.icon name={@icon} class="w-full h-full text-primary" />
          </div>
          {@title}
        </h1>
        <%= if @subtitle do %>
          <p class="text-lg text-gray-500 mt-2 font-medium">
            {@subtitle}
          </p>
        <% end %>
      </div>
      <div :if={@actions != []} class="w-full lg:w-auto">
        {render_slot(@actions)}
      </div>
    </header>
    """
  end

  @doc """
  Renders an SSH connection form for selecting a device and entering a password.
  """
  attr :devices, :list, required: true
  attr :selected_ip, :string, required: true
  attr :password, :string, required: true
  # :disconnected or other
  attr :status, :atom, required: true
  attr :on_change, :string, default: "validate_connection"
  attr :on_submit, :string, default: "connect"
  attr :on_disconnect, :string, default: "disconnect"

  def ssh_connection_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={to_form(%{"ip" => @selected_ip, "password" => @password}, as: :connection)}
      phx-change={@on_change}
      phx-submit={@on_submit}
      class="flex flex-wrap items-end gap-3"
    >
      <div class="w-fit min-w-[140px]">
        <.input
          field={f[:ip]}
          type="select"
          label="Target Device"
          disabled={@status != :disconnected}
          options={[
            {"Select a device...", ""} | Enum.map(@devices, &{&1.name || &1.hostname, &1.ip})
          ]}
        />
      </div>

      <div class="w-28">
        <.input
          field={f[:password]}
          type="password"
          label="SSH Password"
          disabled={@status != :disconnected}
          placeholder="optional"
        />
      </div>

      <div class="flex items-center mb-3">
        <%= if @status == :disconnected do %>
          <button
            type="submit"
            class="btn btn-primary btn-sm rounded-xl shadow-lg shadow-primary/20 flex items-center gap-2 px-6 h-9"
          >
            <.icon name="hero-bolt" class="w-4 h-4" /> Connect
          </button>
        <% else %>
          <button
            type="button"
            phx-click={@on_disconnect}
            class="btn btn-error btn-outline btn-sm rounded-xl flex items-center gap-2 px-6 h-9"
          >
            <.icon name="hero-x-mark" class="w-4 h-4" /> Disconnect
          </button>
        <% end %>
      </div>
    </.form>
    """
  end

  @doc """
  Renders a navigation link for the sidebar.
  """
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  def nav_link(assigns) do
    ~H"""
    <.link
      href={@href}
      class={[
        "flex items-center gap-3 px-4 py-3 rounded-2xl text-sm font-bold transition-all group/link",
        @active && "bg-primary text-white shadow-lg shadow-primary/25",
        !@active && "text-gray-500 hover:bg-gray-50 hover:text-gray-900"
      ]}
    >
      <.icon
        name={@icon}
        class={[
          "w-5 h-5 transition-colors shrink-0",
          @active && "text-white",
          !@active && "text-gray-400 group-hover/link:text-primary"
        ]}
      />
      {render_slot(@inner_block)}
    </.link>
    """
  end
end
