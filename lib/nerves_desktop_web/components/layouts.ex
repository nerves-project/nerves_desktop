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

  attr :active_tab, :atom,
    default: :devices,
    values: [:devices, :console, :burner, :resources, :nerves_key, :fel, :settings]

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <div class="flex h-screen overflow-hidden bg-ground">
      <aside class="z-20 flex w-[13.5rem] shrink-0 flex-col bg-chassis">
        <div class="px-5 py-5">
          <a href="/" class="block w-fit rounded-sm">
            <img
              src={~p"/images/nerves_landscape_inverse.svg"}
              class="h-6 w-auto"
              alt="Nerves Desktop"
            />
          </a>
        </div>

        <nav class="flex-1 space-y-0.5 px-3" aria-label="Main">
          <UI.nav_link href={~p"/"} icon="hero-cpu-chip" active={@active_tab == :devices}>
            Devices
          </UI.nav_link>
          <UI.nav_link href={~p"/console"} icon="hero-command-line" active={@active_tab == :console}>
            Console
          </UI.nav_link>
          <UI.nav_link href={~p"/burner"} icon="hero-bolt" active={@active_tab == :burner}>
            Firmware
          </UI.nav_link>
          <UI.nav_link href={~p"/resources"} icon="hero-book-open" active={@active_tab == :resources}>
            Resources
          </UI.nav_link>
          <UI.nav_link href={~p"/settings"} icon="hero-cog-6-tooth" active={@active_tab == :settings}>
            Settings
          </UI.nav_link>
        </nav>

        <div class="border-t border-chassis-line/60 px-5 py-3">
          <p class="text-xs font-medium text-white">Nerves Desktop</p>
          <p class="mt-0.5 font-mono text-2xs text-chassis-text">
            v{Application.spec(:nerves_desktop, :vsn)}
          </p>
        </div>
      </aside>

      <main class="relative flex min-w-0 flex-1 flex-col overflow-hidden">
        <.flash_group flash={@flash} />
        <div class="flex flex-1 flex-col gap-5 overflow-y-auto px-6 py-6 lg:px-8">
          {render_slot(@inner_block)}
        </div>
      </main>
    </div>
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div
      id={@id}
      aria-live="polite"
      class="pointer-events-none fixed top-4 right-4 z-50 flex w-80 flex-col gap-2"
    >
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title="Lost connection to the app"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Reconnecting <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title="The app stopped responding"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Reconnecting <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end
end
