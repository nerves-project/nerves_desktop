defmodule NervesDesktopWeb.SettingsLive do
  use NervesDesktopWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    ssh_client = Application.get_env(:nerves_desktop, :ssh_client, :erlang_ssh)
    {:ok, assign(socket, page_title: "Settings", ssh_client: ssh_client)}
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
      <UI.page_header title="Settings" subtitle="How this app opens a shell on your boards" />

      <div>
        <UI.panel label="Which SSH client to use">
          <.form for={%{}} id="settings-form" phx-change="save_settings">
            <fieldset class="grid grid-cols-1 gap-3 md:grid-cols-2">
              <legend class="sr-only">SSH client</legend>

              <label
                :for={option <- ssh_clients()}
                class="group relative cursor-pointer rounded-md border border-rule bg-panel p-4 transition-colors has-checked:border-primary has-checked:bg-primary-soft hover:border-rule-strong has-focus-visible:outline-2 has-focus-visible:outline-offset-2 has-focus-visible:outline-secondary"
              >
                <input
                  type="radio"
                  name="ssh_client"
                  value={option.value}
                  checked={@ssh_client == option.key}
                  class="sr-only"
                />
                <span class="flex min-h-7 items-center gap-2">
                  <span class="font-display text-[15px] font-semibold">{option.title}</span>
                  <span :if={@ssh_client == option.key} class="nd-chip nd-chip-live ml-auto">
                    <span class="nd-led"></span> In use
                  </span>
                </span>
                <span class="mt-1 block min-h-[2.75rem] text-[13px] leading-relaxed text-muted">
                  {option.description}
                </span>

                <dl class="mt-3 space-y-1.5 border-t border-rule pt-3">
                  <div :for={{term, value} <- option.traits} class="flex gap-2 text-xs">
                    <dt class="w-24 shrink-0 text-muted">{term}</dt>
                    <dd class="font-medium">{value}</dd>
                  </div>
                </dl>
              </label>
            </fieldset>
          </.form>

          <p class="nd-note nd-note-info mt-4">
            <.icon name="hero-information-circle" class="mt-px size-4 shrink-0 text-primary" />
            <span>
              Takes effect on the next connection. It is held in memory, so it goes back to
              Erlang SSH when the app restarts.
            </span>
          </p>
        </UI.panel>
      </div>
    </Layouts.app>
    """
  end

  defp ssh_clients do
    [
      %{
        key: :system_ssh,
        value: "system_ssh",
        title: "System SSH",
        description: "Shells out to the ssh binary already installed on this machine.",
        traits: [
          {"Your keys", "Yes, via ~/.ssh/config"},
          {"Console size", "Fixed at 80x24"},
          {"Needs", "ssh on your PATH"}
        ]
      },
      %{
        key: :erlang_ssh,
        value: "erlang_ssh",
        title: "Erlang SSH",
        description: "Uses the SSH client that ships inside Erlang itself.",
        traits: [
          {"Your keys", "Password only"},
          {"Console size", "Follows the window"},
          {"Needs", "Nothing else"}
        ]
      }
    ]
  end
end
