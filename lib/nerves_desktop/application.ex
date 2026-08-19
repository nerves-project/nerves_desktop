defmodule NervesDesktop.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    pubsub = System.get_env("ELIXIRKIT_PUBSUB")

    children = [
      NervesDesktopWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:nerves_desktop, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NervesDesktop.PubSub},
      {Registry, keys: :unique, name: NervesDesktop.ConnectionRegistry},
      NervesDesktop.ConnectionSupervisor,
      {ElixirKit.PubSub, connect: pubsub || :ignore, on_exit: fn -> System.stop() end},
      {Task.Supervisor, name: NervesDesktop.TaskSupervisor},
      {NervesDesktop.DeviceScanner, []},
      {NervesDesktop.HostInfo, []},
      NervesDesktopWeb.Endpoint,
      {Task,
       fn ->
         if pubsub do
           {:ok, {_ip, port}} = NervesDesktopWeb.Endpoint.server_info(:http)
           ElixirKit.PubSub.broadcast("messages", "ready:#{port}")
         end
       end}
    ]

    opts = [strategy: :one_for_one, name: NervesDesktop.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    NervesDesktopWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
