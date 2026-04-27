defmodule NervesDesktop.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    pubsub = System.get_env("ELIXIRKIT_PUBSUB")

    children = [
      NervesDesktopWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:nerves_desktop, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: NervesDesktop.PubSub},
      {Task.Supervisor, name: NervesDesktop.TaskSupervisor},
      {NervesDesktop.Discovery, []},
      {NervesDesktop.FelScanner, []},
      {ElixirKit.PubSub, connect: pubsub || :ignore, on_exit: fn -> System.stop() end},
      # Start a worker by calling: NervesDesktop.Worker.start_link(arg)
      # {NervesDesktop.Worker, arg},
      # Start to serve requests, typically the last entry
      NervesDesktopWeb.Endpoint,
      {Task,
       fn ->
         if pubsub do
           ElixirKit.PubSub.broadcast("messages", "ready")
         end
       end}
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: NervesDesktop.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    NervesDesktopWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
