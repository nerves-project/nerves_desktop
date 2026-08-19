defmodule NervesDesktopWeb.UI do
  use Phoenix.Component
  import NervesDesktopWeb.CoreComponents

  @doc """
  Renders a page header: title, one-line summary, and an actions slot.

  The page is already named in the sidebar, so the header stays quiet and
  gives its weight to the actions instead.
  """
  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class="flex flex-col gap-3 border-b border-rule pb-4 lg:flex-row lg:items-center lg:justify-between lg:gap-6">
      <div class="min-w-0">
        <h1 class="font-display text-[1.625rem] leading-tight font-semibold">{@title}</h1>
        <p :if={@subtitle} class="mt-0.5 text-[13px] text-muted">{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="shrink-0">{render_slot(@actions)}</div>
    </header>
    """
  end

  @doc """
  Renders a panel: the app's one container.

  The `label` sits on the rule that bounds the panel. Pass `step` when the
  panels form a real sequence, and `done` once that step is satisfied.
  """
  attr :label, :string, default: nil
  attr :step, :integer, default: nil
  attr :done, :boolean, default: false
  attr :class, :any, default: nil
  attr :body_class, :any, default: "p-4"
  attr :rest, :global
  slot :actions
  slot :inner_block, required: true

  def panel(assigns) do
    ~H"""
    <section class={["nd-panel flex flex-col", @class]} {@rest}>
      <div
        :if={@label || @step}
        class="flex items-center gap-2.5 rounded-t-[9px] border-b border-rule bg-sunk px-4 py-2.5"
      >
        <span
          :if={@step}
          class={[
            "flex size-5 shrink-0 items-center justify-center rounded-full font-mono text-2xs font-semibold text-white transition-colors",
            (@done && "bg-live") || "bg-primary"
          ]}
        >
          <.icon :if={@done} name="hero-check" class="size-3" />
          <span :if={!@done}>{@step}</span>
        </span>
        <span class="nd-legend min-w-0 flex-1">
          <span class="truncate">{@label}</span>
        </span>
        <div :if={@actions != []} class="flex shrink-0 items-center gap-1">
          {render_slot(@actions)}
        </div>
      </div>
      <div class={["min-h-0 flex-1", @body_class]}>{render_slot(@inner_block)}</div>
    </section>
    """
  end

  @doc """
  Renders the discovery readout: whether scanning is live, when it last ran,
  and a control to run it again.
  """
  attr :last_scan_at, :any, required: true
  attr :id, :string, default: "scanning-status"
  attr :on_refresh, :string, default: nil
  attr :class, :string, default: nil

  def scanning_status(assigns) do
    ~H"""
    <div class={["flex items-center gap-3", @class]}>
      <span class="nd-chip nd-chip-live">
        <span class="nd-led motion-safe:animate-pulse"></span> Scanning
      </span>

      <p class="text-xs text-muted">
        Last swept
        <time
          id={@id}
          datetime={DateTime.to_iso8601(@last_scan_at)}
          phx-hook="LocalTime"
          class="font-mono tabular-nums text-ink"
        >
          {Calendar.strftime(@last_scan_at, "%H:%M:%S")}
        </time>
      </p>

      <button
        :if={@on_refresh}
        phx-click={@on_refresh}
        phx-throttle="2000"
        class="nd-btn nd-btn-secondary"
      >
        <.icon name="hero-arrow-path" class="size-4" /> Scan now
      </button>
    </div>
    """
  end

  @doc """
  Renders the console connection bar: pick a device, optionally supply a
  password, and open or close the session.
  """
  attr :devices, :list, required: true
  attr :selected_target, :string, required: true
  attr :password, :string, required: true
  attr :status, :atom, required: true, values: [:connected, :disconnected]
  attr :on_change, :string, default: "validate_connection"
  attr :on_submit, :string, default: "connect"
  attr :on_disconnect, :string, default: "disconnect"

  def ssh_connection_form(assigns) do
    ~H"""
    <.form
      :let={f}
      for={to_form(%{"target" => @selected_target, "password" => @password}, as: :connection)}
      id="connection-form"
      phx-change={@on_change}
      phx-submit={@on_submit}
      class="flex flex-wrap items-end gap-3"
    >
      <div class="w-56">
        <.input
          field={f[:target]}
          type="select"
          label="Device"
          disabled={@status != :disconnected}
          options={[
            {"Select a device", ""}
            | Enum.map(@devices, &{&1[:name] || &1[:hostname], &1[:target]})
          ]}
        />
      </div>

      <div class="w-40">
        <.input
          field={f[:password]}
          type="password"
          label="Password"
          disabled={@status != :disconnected}
          placeholder="Leave blank for keys"
          autocomplete="off"
        />
      </div>

      <%= if @status == :disconnected do %>
        <button type="submit" class="nd-btn nd-btn-primary">
          <.icon name="hero-bolt" class="size-4" /> Connect
        </button>
      <% else %>
        <button type="button" phx-click={@on_disconnect} class="nd-btn nd-btn-secondary">
          <.icon name="hero-x-mark" class="size-4" /> Disconnect
        </button>
      <% end %>
    </.form>
    """
  end

  @doc """
  Renders an empty or waiting state inside a panel.
  """
  attr :icon, :string, default: nil
  attr :class, :string, default: nil
  slot :inner_block, required: true

  def placeholder(assigns) do
    ~H"""
    <div class={[
      "flex items-center justify-center gap-2 rounded-md border border-dashed border-rule-strong bg-sunk px-4 py-6 text-center text-[13px] text-muted",
      @class
    ]}>
      <.icon :if={@icon} name={@icon} class="size-4 shrink-0 text-faint" />
      <div>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  @doc """
  Renders a sidebar navigation link.
  """
  attr :href, :string, required: true
  attr :icon, :string, required: true
  attr :active, :boolean, default: false
  slot :inner_block, required: true

  def nav_link(assigns) do
    ~H"""
    <.link
      href={@href}
      aria-current={@active && "page"}
      class={["nd-nav-link", @active && "nd-nav-link-active"]}
    >
      <.icon name={@icon} class="nd-nav-icon size-4 shrink-0 transition-colors" />
      {render_slot(@inner_block)}
    </.link>
    """
  end

  @doc """
  Renders a value that copies to the clipboard when clicked.
  """
  attr :value, :string, default: nil
  attr :class, :string, default: nil
  attr :fallback, :string, default: "unknown"

  def copyable(assigns) do
    ~H"""
    <button
      :if={@value}
      type="button"
      phx-click={Phoenix.LiveView.JS.dispatch("phx:copy", detail: %{text: @value})}
      title={"Copy #{@value}"}
      class={["nd-copy group/copy", @class]}
    >
      <span class="truncate">{@value}</span>
      <.icon
        name="hero-clipboard"
        class="size-3 shrink-0 opacity-0 transition-opacity group-hover/copy:opacity-100"
      />
    </button>
    <span :if={!@value} class={["font-mono text-xs text-faint", @class]}>{@fallback}</span>
    """
  end
end
