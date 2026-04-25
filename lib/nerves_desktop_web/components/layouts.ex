defmodule NervesDesktopWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use NervesDesktopWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders your app layout.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :active_tab, :atom, default: :devices, values: [:devices, :console, :burner]
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex h-screen bg-base-200/50 overflow-hidden">
      <!-- Sidebar -->
      <aside class="w-64 bg-white border-r border-gray-100 flex flex-col shadow-xl shadow-gray-200/50 z-20 transition-all duration-300 group">
        <div class="p-6">
          <a href="/" class="flex items-center gap-3 overflow-hidden whitespace-nowrap">
            <img src={~p"/images/nerves_landscape.svg"} class="h-10 w-auto" alt="Nerves" />
          </a>
        </div>

        <nav class="flex-1 px-4 space-y-2 mt-4">
          <.nav_link href={~p"/"} icon="hero-list-bullet" active={@active_tab == :devices}>
            Devices
          </.nav_link>
          <.nav_link href={~p"/console"} icon="hero-command-line" active={@active_tab == :console}>
            Device Console
          </.nav_link>
          <.nav_link href={~p"/burner"} icon="hero-fire" active={@active_tab == :burner}>
            Firmware Burner
          </.nav_link>
        </nav>

        <div class="p-6 border-t border-gray-50 overflow-hidden">
          <div class="flex items-center gap-3 px-2 py-3 bg-gray-50 rounded-2xl border border-gray-100 whitespace-nowrap">
            <div class="w-8 h-8 shrink-0">
              <img src={~p"/images/nerves_icon.svg"} class="w-full h-full" alt="ND" />
            </div>
            <div class="flex-1 min-w-0">
              <p class="text-xs font-bold text-gray-900 truncate">Nerves Desktop</p>
              <p class="text-[10px] text-gray-400 truncate">v{Application.spec(:nerves_desktop, :vsn)}</p>
            </div>
          </div>
        </div>
      </aside>

      <!-- Main Content -->
      <main class="flex-1 flex flex-col min-w-0 overflow-hidden relative">
        <div class="flex-1 overflow-y-auto relative">
          <.flash_group flash={@flash} />
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>
    """
  end

  defp nav_link(assigns) do
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

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="fixed top-4 right-4 z-50 flex flex-col gap-2 w-80">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
