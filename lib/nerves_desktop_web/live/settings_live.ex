defmodule NervesDesktopWeb.SettingsLive do
  use NervesDesktopWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    ssh_client = Application.get_env(:nerves_desktop, :ssh_client, :system_ssh)
    {:ok, assign(socket, ssh_client: ssh_client)}
  end

  @impl true
  def handle_event("save_settings", %{"ssh_client" => ssh_client}, socket) do
    ssh_client = String.to_existing_atom(ssh_client)
    Application.put_env(:nerves_desktop, :ssh_client, ssh_client)
    {:noreply, assign(socket, ssh_client: ssh_client) |> put_flash(:info, "Settings saved.")}
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

      <div class="bg-white rounded-[2rem] shadow-sm border border-gray-100 p-8">
        <div class="max-w-2xl mx-auto">
          <h3 class="text-xl font-bold text-gray-900 mb-6 flex items-center gap-2">
            <.icon name="hero-command-line" class="w-6 h-6 text-primary" />
            Connection Settings
          </h3>

          <.form for={%{}} phx-change="save_settings" class="space-y-8">
            <div class="grid grid-cols-1 md:grid-cols-2 gap-6">
              <label class="group cursor-pointer">
                <input
                  type="radio"
                  name="ssh_client"
                  value="system_ssh"
                  checked={@ssh_client == :system_ssh}
                  class="peer hidden"
                />
                <div class="p-6 rounded-2xl border-2 border-gray-100 transition-all peer-checked:border-primary peer-checked:bg-primary/[0.02] group-hover:border-gray-200 h-full">
                  <div class="flex items-center gap-4 mb-4">
                    <div class="p-3 bg-gray-50 rounded-xl group-hover:bg-white transition-colors">
                      <.icon name="hero-cpu-chip" class="w-6 h-6 text-gray-400" />
                    </div>
                    <div>
                      <h4 class="font-bold text-gray-900">System SSH</h4>
                      <p class="text-xs text-gray-500">Uses your host's SSH binary</p>
                    </div>
                  </div>
                  <p class="text-sm text-gray-500 leading-relaxed">
                    Uses the <code class="bg-gray-100 px-1 rounded">ssh</code> command on your system. Best compatibility with local SSH keys and configurations.
                  </p>
                </div>
              </label>

              <label class="group cursor-pointer">
                <input
                  type="radio"
                  name="ssh_client"
                  value="erlang_ssh"
                  checked={@ssh_client == :erlang_ssh}
                  class="peer hidden"
                />
                <div class="p-6 rounded-2xl border-2 border-gray-100 transition-all peer-checked:border-primary peer-checked:bg-primary/[0.02] group-hover:border-gray-200 h-full">
                  <div class="flex items-center gap-4 mb-4">
                    <div class="p-3 bg-gray-50 rounded-xl group-hover:bg-white transition-colors">
                      <.icon name="hero-beaker" class="w-6 h-6 text-gray-400" />
                    </div>
                    <div>
                      <h4 class="font-bold text-gray-900">Erlang SSH</h4>
                      <p class="text-xs text-gray-500">Native Elixir implementation</p>
                    </div>
                  </div>
                  <p class="text-sm text-gray-500 leading-relaxed">
                    Uses the built-in Erlang SSH application. Faster and doesn't depend on external tools.
                  </p>
                </div>
              </label>
            </div>
          </.form>

          <div class="mt-12 pt-8 border-t border-gray-50">
            <div class="flex items-center gap-4 text-gray-400">
              <.icon name="hero-information-circle" class="w-5 h-5" />
              <p class="text-sm">
                Settings are saved in memory for the current session and will be lost on application restart.
              </p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
