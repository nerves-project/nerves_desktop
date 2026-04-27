defmodule NervesDesktopWeb.SettingsLive do
  use NervesDesktopWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:settings}>
      <UI.page_header
        icon="hero-cog-6-tooth"
        title="Settings"
        subtitle="Configure Nerves Desktop settings"
      />

      <div class="bg-white rounded-3xl shadow-sm border border-gray-100 p-8">
        <div class="flex flex-col items-center justify-center py-20 text-center">
          <div class="p-6 bg-gray-50 rounded-full mb-6">
            <.icon name="hero-wrench-screwdriver" class="w-12 h-12 text-gray-400" />
          </div>
          <h3 class="text-xl font-bold text-gray-900 mb-2">Settings are coming soon</h3>
          <p class="text-gray-500 max-w-sm">
            We're working on bringing you more configuration options for your Nerves Desktop experience.
          </p>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
