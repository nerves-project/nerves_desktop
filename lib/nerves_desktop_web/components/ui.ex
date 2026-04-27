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
      "flex items-center gap-6 bg-white p-2 pr-4 rounded-2xl shadow-sm border border-gray-100",
      @class
    ]}>
      <div class="flex flex-col items-end px-2">
        <span class="text-[10px] uppercase tracking-wider font-bold text-gray-400">Status</span>
        <div class="flex items-center gap-2">
          <span class="relative flex h-2 w-2">
            <span class="animate-ping absolute inline-flex h-full w-full rounded-full bg-green-400 opacity-75">
            </span>
            <span class="relative inline-flex rounded-full h-2 w-2 bg-green-500"></span>
          </span>
          <span class="text-sm font-semibold text-gray-700">Auto-scanning</span>
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
