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

  @doc """
  Returns a list of environment variables ensuring a UTF-8 locale is set,
  derived from the OS locale provided by the Tauri frontend.
  Suitable for passing to Port.open.
  """
  def utf8_env do
    state = get()

    # Tauri returns locale as "en-US", we want "en_US.UTF-8"
    base_locale = Map.get(state, "locale")

    lang =
      if is_binary(base_locale) and base_locale != "" do
        "#{String.replace(base_locale, "-", "_")}.UTF-8"
      else
        "en_US.UTF-8"
      end

    [
      {~c"LANG", String.to_charlist(lang)},
      {~c"LC_ALL", String.to_charlist(lang)},
      {~c"TERM", ~c"xterm-256color"}
    ]
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
