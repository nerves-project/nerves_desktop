defmodule NervesDesktopWeb.ResourcesLive do
  use NervesDesktopWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, resource_groups: nerves_resources())}
  end

  @impl true
  def handle_event("open_url", %{"url" => url}, socket) do
    if System.get_env("ELIXIRKIT_PUBSUB") do
      ElixirKit.PubSub.broadcast("opener", url)
    end

    {:noreply, socket}
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
                        <button
                          phx-click="open_url"
                          phx-value-url={item.hex}
                          class="text-gray-400 hover:text-primary flex items-center gap-1.5 transition-colors"
                        >
                          <.icon name="hero-cube" class="w-4 h-4" /> Hex
                        </button>
                      <% end %>
                      <%= if item[:github] do %>
                        <span :if={item[:hex]} class="text-gray-200">|</span>
                        <button
                          phx-click="open_url"
                          phx-value-url={item.github}
                          class="text-gray-400 hover:text-primary flex items-center gap-1.5 transition-colors"
                        >
                          <.icon name="hero-code-bracket" class="w-4 h-4" /> GitHub
                        </button>
                      <% end %>
                      <%= if item[:url] do %>
                        <button
                          phx-click="open_url"
                          phx-value-url={item.url}
                          class="text-primary font-bold hover:underline flex items-center gap-1.5"
                        >
                          Visit Site <.icon name="hero-arrow-top-right-on-square" class="w-4 h-4" />
                        </button>
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
            desc:
              "Official Nerves community for real-time discussions, questions and announcements"
          },
          %{
            name: "Nerves Meetup EU",
            url: "https://nervesmeetup.eu/nerves-meetup-europe/",
            desc: "Remote meetups via Zoom, every second Wednesday of the month at 19h CET"
          }
        ]
      },
      %{
        title: "Core Framework",
        icon: "hero-cpu-chip",
        links: [
          %{
            name: "nerves",
            github: "https://github.com/nerves-project/nerves",
            hex: "https://hex.pm/packages/nerves",
            desc:
              "The main Nerves framework, docs, and developer entry point for embedded Elixir projects."
          },
          %{
            name: "nerves_system_br",
            github: "https://github.com/nerves-project/nerves_system_br",
            hex: "https://hex.pm/packages/nerves_system_br",
            desc: "Buildroot-based system foundation used to build and maintain Nerves targets."
          },
          %{
            name: "nerves_runtime",
            github: "https://github.com/nerves-project/nerves_runtime",
            hex: "https://hex.pm/packages/nerves_runtime",
            desc:
              "Shared runtime utilities and initialization helpers commonly used on Nerves devices."
          },
          %{
            name: "erlinit",
            github: "https://github.com/nerves-project/erlinit",
            desc:
              "A minimal init process that boots and supervises Erlang/OTP releases on devices."
          },
          %{
            name: "ring_logger",
            github: "https://github.com/nerves-project/ring_logger",
            hex: "https://hex.pm/packages/ring_logger",
            desc:
              "Logger backend that keeps recent logs in memory for debugging constrained devices."
          },
          %{
            name: "ramoops_logger",
            github: "https://github.com/nerves-project/ramoops_logger",
            hex: "https://hex.pm/packages/ramoops_logger",
            desc:
              "Logger backend that writes crash and boot diagnostics to the Linux ramoops driver."
          },
          %{
            name: "nerves_pack",
            github: "https://github.com/nerves-project/nerves_pack",
            hex: "https://hex.pm/packages/nerves_pack",
            desc: "Packages device initialization pieces that many Nerves systems need at boot."
          },
          %{
            name: "nerves_bootstrap",
            github: "https://github.com/nerves-project/nerves_bootstrap",
            hex: "https://hex.pm/packages/nerves_bootstrap",
            desc:
              "Mix integration and project generator for creating and bootstrapping Nerves apps."
          },
          %{
            name: "shoehorn",
            github: "https://github.com/nerves-project/shoehorn",
            hex: "https://hex.pm/packages/shoehorn",
            desc: "Helps manage OTP startup order and failure handling during early system boot."
          },
          %{
            name: "nerves_heart",
            github: "https://github.com/nerves-project/nerves_heart",
            desc: "Adds Erlang heart support so systems can recover from VM crashes."
          },
          %{
            name: "nerves_logging",
            github: "https://github.com/nerves-project/nerves_logging",
            hex: "https://hex.pm/packages/nerves_logging",
            desc: "Routes Linux and system log messages into Elixir Logger for unified logging."
          },
          %{
            name: "nerves_uevent",
            github: "https://github.com/nerves-project/nerves_uevent",
            hex: "https://hex.pm/packages/nerves_uevent",
            desc: "Monitors Linux uevents so apps can react to hardware attach and detach events."
          }
        ]
      },
      %{
        title: "Learning & Resources",
        icon: "hero-academic-cap",
        links: [
          %{
            name: "nerves_examples",
            github: "https://github.com/nerves-project/nerves_examples",
            desc: "A broad set of example apps that show common Nerves patterns and integrations."
          },
          %{
            name: "nerves_livebook",
            github: "https://github.com/nerves-livebook/nerves_livebook",
            desc:
              "Runs Livebook on embedded devices for interactive development and remote exploration."
          },
          %{
            name: "circuits_quickstart",
            github: "https://github.com/elixir-circuits/circuits_quickstart",
            desc: "A fast way to try Elixir Circuits and Nerves with prebuilt firmware."
          },
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
      },
      %{
        title: "Hardware Targets",
        icon: "hero-cpu-chip",
        links: [
          %{
            name: "nerves_system_rpi0",
            github: "https://github.com/nerves-project/nerves_system_rpi0",
            hex: "https://hex.pm/packages/nerves_system_rpi0",
            desc: "Official Nerves system for Raspberry Pi Zero and Zero W boards."
          },
          %{
            name: "nerves_system_rpi0_2",
            github: "https://github.com/nerves-project/nerves_system_rpi0_2",
            hex: "https://hex.pm/packages/nerves_system_rpi0_2",
            desc: "Target for Raspberry Pi Zero 2 W and compatible small-form-factor Pi hardware."
          },
          %{
            name: "nerves_system_rpi",
            github: "https://github.com/nerves-project/nerves_system_rpi",
            hex: "https://hex.pm/packages/nerves_system_rpi",
            desc: "Official target for Raspberry Pi A+ and B+ boards."
          },
          %{
            name: "nerves_system_rpi2",
            github: "https://github.com/nerves-project/nerves_system_rpi2",
            hex: "https://hex.pm/packages/nerves_system_rpi2",
            desc: "Official Raspberry Pi 2 target for older Pi hardware."
          },
          %{
            name: "nerves_system_rpi3",
            github: "https://github.com/nerves-project/nerves_system_rpi3",
            hex: "https://hex.pm/packages/nerves_system_rpi3",
            desc: "Official Raspberry Pi 3 target for building and deploying Nerves firmware."
          },
          %{
            name: "nerves_system_rpi3a",
            github: "https://github.com/nerves-project/nerves_system_rpi3a",
            hex: "https://hex.pm/packages/nerves_system_rpi3a",
            desc: "Target for Raspberry Pi 3A+ and closely related compact Pi boards."
          },
          %{
            name: "nerves_system_rpi4",
            github: "https://github.com/nerves-project/nerves_system_rpi4",
            hex: "https://hex.pm/packages/nerves_system_rpi4",
            desc:
              "Official Raspberry Pi 4 target with the system packages and boot setup you need."
          },
          %{
            name: "nerves_system_rpi5",
            github: "https://github.com/nerves-project/nerves_system_rpi5",
            hex: "https://hex.pm/packages/nerves_system_rpi5",
            desc: "Official Raspberry Pi 5 target for newer Pi-based deployments."
          },
          %{
            name: "nerves_system_bbb",
            github: "https://github.com/nerves-project/nerves_system_bbb",
            hex: "https://hex.pm/packages/nerves_system_bbb",
            desc: "Official BeagleBone-based target for building Nerves firmware images."
          },
          %{
            name: "nerves_system_x86_64",
            github: "https://github.com/nerves-project/nerves_system_x86_64",
            hex: "https://hex.pm/packages/nerves_system_x86_64",
            desc:
              "Generic x86_64 target useful for PCs, industrial hardware, and some testing flows."
          },
          %{
            name: "nerves_system_mangopi_mq_pro",
            github: "https://github.com/nerves-project/nerves_system_mangopi_mq_pro",
            hex: "https://hex.pm/packages/nerves_system_mangopi_mq_pro",
            desc: "Official MangoPi MQ-Pro target for ARM-based Nerves deployments."
          },
          %{
            name: "nerves_system_grisp2",
            github: "https://github.com/nerves-project/nerves_system_grisp2",
            hex: "https://hex.pm/packages/nerves_system_grisp2",
            desc:
              "Official target for the GRiSP 2 board and its Erlang-focused hardware platform."
          },
          %{
            name: "nerves_system_vultr",
            github: "https://github.com/nerves-project/nerves_system_vultr",
            hex: "https://hex.pm/packages/nerves_system_vultr",
            desc: "Experimental target for running Nerves in a Vultr cloud VM environment."
          },
          %{
            name: "nerves_system_qemu_aarch64",
            github: "https://github.com/nerves-project/nerves_system_qemu_aarch64",
            hex: "https://hex.pm/packages/nerves_system_qemu_aarch64",
            desc:
              "QEMU-based aarch64 target for running and testing Nerves in virtualized environments."
          },
          %{
            name: "nerves_system_osd32mp1",
            github: "https://github.com/nerves-project/nerves_system_osd32mp1",
            hex: "https://hex.pm/packages/nerves_system_osd32mp1",
            desc: "Official target for boards based on the Octavo OSD32MP1 platform."
          }
        ]
      },
      %{
        title: "Hardware Access",
        icon: "hero-bolt",
        links: [
          %{
            name: "circuits_uart",
            github: "https://github.com/elixir-circuits/circuits_uart",
            hex: "https://hex.pm/packages/circuits_uart",
            desc:
              "Elixir library for discovering serial devices and talking over UART connections."
          },
          %{
            name: "circuits_gpio",
            github: "https://github.com/elixir-circuits/circuits_gpio",
            hex: "https://hex.pm/packages/circuits_gpio",
            desc:
              "Elixir interface for reading and controlling GPIO pins on embedded Linux hardware."
          },
          %{
            name: "circuits_i2c",
            github: "https://github.com/elixir-circuits/circuits_i2c",
            hex: "https://hex.pm/packages/circuits_i2c",
            desc: "Elixir interface for talking to sensors and peripherals over I2C buses."
          },
          %{
            name: "circuits_spi",
            github: "https://github.com/elixir-circuits/circuits_spi",
            hex: "https://hex.pm/packages/circuits_spi",
            desc: "Elixir interface for communicating with chips and displays over SPI."
          },
          %{
            name: "nerves_leds",
            github: "https://github.com/nerves-project/nerves_leds",
            hex: "https://hex.pm/packages/nerves_leds",
            desc: "Older helper library for driving status LEDs on embedded boards."
          },
          %{
            name: "boardid",
            github: "https://github.com/nerves-project/boardid",
            desc: "Small utility for reading board-specific serial or identity information."
          },
          %{
            name: "uboot_env",
            github: "https://github.com/nerves-project/uboot_env",
            hex: "https://hex.pm/packages/uboot_env",
            desc: "Reads and writes U-Boot environment blocks from Elixir code."
          }
        ]
      },
      %{
        title: "Networking",
        icon: "hero-wifi",
        links: [
          %{
            name: "vintage_net",
            github: "https://github.com/nerves-networking/vintage_net",
            hex: "https://hex.pm/packages/vintage_net",
            desc:
              "Core networking library for configuring and managing Nerves device connections."
          },
          %{
            name: "vintage_net_wifi",
            github: "https://github.com/nerves-networking/vintage_net_wifi",
            hex: "https://hex.pm/packages/vintage_net_wifi",
            desc: "Wi-Fi support layer for VintageNet-based network configuration."
          },
          %{
            name: "vintage_net_mobile",
            github: "https://github.com/nerves-networking/vintage_net_mobile",
            hex: "https://hex.pm/packages/vintage_net_mobile",
            desc: "Cellular and mobile networking support for Nerves devices."
          },
          %{
            name: "vintage_net_wireguard",
            github: "https://github.com/nerves-networking/vintage_net_wireguard",
            hex: "https://hex.pm/packages/vintage_net_wireguard",
            desc: "Adds WireGuard VPN support to the VintageNet networking stack."
          },
          %{
            name: "vintage_net_qmi",
            github: "https://github.com/nerves-networking/vintage_net_qmi",
            hex: "https://hex.pm/packages/vintage_net_qmi",
            desc: "QMI modem integration for cellular networking with VintageNet."
          },
          %{
            name: "vintage_net_ethernet",
            github: "https://github.com/nerves-networking/vintage_net_ethernet",
            hex: "https://hex.pm/packages/vintage_net_ethernet",
            desc: "Ethernet support layer for the VintageNet networking stack."
          },
          %{
            name: "vintage_net_direct",
            github: "https://github.com/nerves-networking/vintage_net_direct",
            hex: "https://hex.pm/packages/vintage_net_direct",
            desc: "Support for direct host-to-device networking setups with VintageNet."
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
        title: "Remote Access",
        icon: "hero-command-line",
        links: [
          %{
            name: "toolshed",
            github: "https://github.com/elixir-toolshed/toolshed",
            hex: "https://hex.pm/packages/toolshed",
            desc: "Handy shell-like IEx helpers that make on-device troubleshooting much easier."
          },
          %{
            name: "nerves_ssh",
            github: "https://github.com/nerves-project/nerves_ssh",
            hex: "https://hex.pm/packages/nerves_ssh",
            desc: "SSH server integration and subsystems for secure remote device access."
          },
          %{
            name: "ssh_subsystem_fwup",
            github: "https://github.com/nerves-project/ssh_subsystem_fwup",
            hex: "https://hex.pm/packages/ssh_subsystem_fwup",
            desc: "Enables firmware update workflows over SSH using an Erlang subsystem."
          },
          %{
            name: "nerves_motd",
            github: "https://github.com/nerves-project/nerves_motd",
            hex: "https://hex.pm/packages/nerves_motd",
            desc: "Displays a device-specific message of the day in remote shell sessions."
          }
        ]
      },
      %{
        title: "Build & Infrastructure",
        icon: "hero-wrench-screwdriver",
        links: [
          %{
            name: "Nerves Hub",
            github: "https://github.com/nerves-hub/nerves_hub_web",
            desc: "Over-the-air (OTA) firmware update server."
          },
          %{
            name: "Fwup",
            github: "https://github.com/fhunleth/fwup",
            desc: "Configurable embedded firmware update utility."
          },
          %{
            name: "toolchains",
            github: "https://github.com/nerves-project/toolchains",
            desc: "Monorepo for the cross-compilers used to build Nerves firmware consistently."
          },
          %{
            name: "nerves_systems",
            github: "https://github.com/nerves-project/nerves_systems",
            desc: "Scripts and helpers for maintaining many Nerves system repositories together."
          },
          %{
            name: "nerves_system_linter",
            github: "https://github.com/nerves-project/nerves_system_linter",
            hex: "https://hex.pm/packages/nerves_system_linter",
            desc: "Mix task for checking and validating Nerves system configuration files."
          }
        ]
      },
      %{
        title: "Data & State",
        icon: "hero-circle-stack",
        links: [
          %{
            name: "alarmist",
            github: "https://github.com/nerves-project/alarmist",
            hex: "https://hex.pm/packages/alarmist",
            desc:
              "Alarm handling library for raising, tracking, and reacting to system conditions."
          },
          %{
            name: "property_table",
            github: "https://github.com/nerves-project/property_table",
            hex: "https://hex.pm/packages/property_table",
            desc: "In-memory key-value store with subscriptions, useful for shared device state."
          }
        ]
      }
    ]
  end
end
