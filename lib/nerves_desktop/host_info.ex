defmodule NervesDesktop.HostInfo do
  use GenServer
  require Logger

  @topic "host_info"

  @doc """
  Starts the HostInfo GenServer.
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Returns the current system information map.
  """
  def get do
    GenServer.call(__MODULE__, :get)
  end

  @impl true
  def init(_opts) do
    if System.get_env("ELIXIRKIT_PUBSUB") do
      ElixirKit.PubSub.subscribe(@topic)
    end

    {:ok, %{}}
  end

  @impl true
  def handle_call(:get, _from, state) do
    {:reply, state, state}
  end

  @impl true
  def handle_info(payload, _state) do
    case Jason.decode(payload) do
      {:ok, info} ->
        Logger.info("[HostInfo] Received system info: #{inspect(info)}")
        {:noreply, info}

      {:error, reason} ->
        Logger.error("[HostInfo] Failed to decode host info: #{inspect(reason)}")
        {:noreply, %{}}
    end
  end
end
