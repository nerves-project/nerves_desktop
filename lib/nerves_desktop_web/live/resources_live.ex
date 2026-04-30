defmodule NervesDesktopWeb.ResourcesLive do
  use NervesDesktopWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, resource_groups: nerves_resources())}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} active_tab={:resources}>
      <UI.page_header
        icon="hero-book-open"
        title="Nerves Resources"
        subtitle="Explore documentation, packages, and community resources"
      />

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-5">
        <%= for group <- @resource_groups do %>
          <div class="bg-white rounded-[2rem] shadow-sm border border-gray-100 p-8 flex flex-col h-full overflow-hidden relative group/card">
            <div class="relative z-10 flex flex-col h-full">
              <div class="flex items-center gap-4 mb-6">
                <div class="p-3 bg-gray-50 rounded-xl text-primary group-hover/card:bg-primary group-hover/card:text-white transition-colors duration-300">
                  <.icon name={group.icon} class="w-7 h-7" />
                </div>
                <h3 class="text-2xl font-extrabold text-gray-900 tracking-tight">{group.title}</h3>
              </div>

              <div class="space-y-6 flex-1">
                <%= for item <- group.links do %>
                  <div class="flex flex-col gap-1.5">
                    <div class="text-base font-bold text-gray-800">{item.name}</div>
                    <p :if={item[:desc]} class="text-sm text-gray-500 leading-relaxed">
                      {item.desc}
                    </p>
                    <div class="flex items-center gap-4 text-sm mt-1">
                      <%= if item[:hex] do %>
                        <a
                          href={item.hex}
                          target="_blank"
                          class="text-gray-400 hover:text-primary flex items-center gap-1.5 transition-colors"
                        >
                          <.icon name="hero-cube" class="w-4 h-4" /> Hex
                        </a>
                      <% end %>
                      <%= if item[:github] do %>
                        <span :if={item[:hex]} class="text-gray-200">|</span>
                        <a
                          href={item.github}
                          target="_blank"
                          class="text-gray-400 hover:text-primary flex items-center gap-1.5 transition-colors"
                        >
                          <.icon name="hero-code-bracket" class="w-4 h-4" /> GitHub
                        </a>
                      <% end %>
                      <%= if item[:url] do %>
                        <a
                          href={item.url}
                          target="_blank"
                          class="text-primary font-bold hover:underline flex items-center gap-1.5"
                        >
                          Visit Site <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                        </a>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </Layouts.app>
    """
  end

  defp nerves_resources do
    [
      %{
        title: "Communities",
        icon: "hero-user-group",
        links: [
          %{
            name: "Nerves Discord",
            url: "https://discord.gg/nerves-project",
            desc: "Real-time chat with the Nerves community."
          },
          %{
            name: "Elixir Slack (#nerves)",
            url: "https://elixir-slack.herokuapp.com/",
            desc: "Join the #nerves channel on the official Elixir Slack."
          },
          %{
            name: "Nerves Meetup EU",
            url: "https://www.meetup.com/nerves-meetup-europe/",
            desc: "Regular virtual meetups for the European Nerves community."
          }
        ]
      },
      %{
        title: "Core Framework",
        icon: "hero-cpu-chip",
        links: [
          %{
            name: "Nerves Project",
            hex: "https://hex.pm/packages/nerves",
            github: "https://github.com/nerves-project/nerves",
            desc: "The primary framework for building Elixir-based embedded systems."
          },
          %{
            name: "Nerves System BR",
            github: "https://github.com/nerves-project/nerves_system_br",
            desc: "Buildroot-based base system for Nerves targets."
          },
          %{
            name: "Nerves Toolchain",
            github: "https://github.com/nerves-project/toolchains",
            desc: "Cross-compilation toolchains for various architectures."
          }
        ]
      },
      %{
        title: "Networking",
        icon: "hero-wifi",
        links: [
          %{
            name: "VintageNet",
            hex: "https://hex.pm/packages/vintage_net",
            github: "https://github.com/nerves-networking/vintage_net",
            desc: "Network configuration and management for Nerves."
          },
          %{
            name: "VintageNet WiFi",
            hex: "https://hex.pm/packages/vintage_net_wifi",
            github: "https://github.com/nerves-networking/vintage_net_wifi",
            desc: "WiFi configuration support for VintageNet."
          },
          %{
            name: "MdnsLite",
            hex: "https://hex.pm/packages/mdns_lite",
            github: "https://github.com/nerves-networking/mdns_lite",
            desc: "Simple mDNS advertiser and resolver."
          }
        ]
      },
      %{
        title: "Circuits (Hardware)",
        icon: "hero-bolt",
        links: [
          %{
            name: "Circuits.UART",
            hex: "https://hex.pm/packages/circuits_uart",
            github: "https://github.com/elixir-circuits/circuits_uart",
            desc: "Communicate with serial ports in Elixir."
          },
          %{
            name: "Circuits.GPIO",
            hex: "https://hex.pm/packages/circuits_gpio",
            github: "https://github.com/elixir-circuits/circuits_gpio",
            desc: "Control General Purpose Input/Output (GPIO) pins."
          },
          %{
            name: "Circuits.I2C",
            hex: "https://hex.pm/packages/circuits_i2c",
            github: "https://github.com/elixir-circuits/circuits_i2c",
            desc: "Communicate with I2C devices."
          }
        ]
      },
      %{
        title: "Infrastructure",
        icon: "hero-server-stack",
        links: [
          %{
            name: "Nerves Hub",
            github: "https://github.com/nerves-hub/nerves_hub_web",
            desc: "Over-the-air (OTA) firmware update server."
          },
          %{
            name: "Nerves SSH",
            hex: "https://hex.pm/packages/nerves_ssh",
            github: "https://github.com/nerves-project/nerves_ssh",
            desc: "SSH console support for Nerves devices."
          },
          %{
            name: "Fwup",
            github: "https://github.com/fhunleth/fwup",
            desc: "Configurable embedded firmware update utility."
          }
        ]
      },
      %{
        title: "Learning & Docs",
        icon: "hero-academic-cap",
        links: [
          %{
            name: "Official Documentation",
            url: "https://hexdocs.pm/nerves/getting-started.html",
            desc: "The definitive guide to getting started with Nerves."
          },
          %{
            name: "Nerves Website",
            url: "https://nerves-project.org",
            desc: "Project news, features, and case studies."
          },
          %{
            name: "Elixir Forum",
            url: "https://elixirforum.com/c/elixir-frameworks/nerves/14",
            desc: "Connect with others and ask questions in the Nerves community."
          }
        ]
      }
    ]
  end
end
