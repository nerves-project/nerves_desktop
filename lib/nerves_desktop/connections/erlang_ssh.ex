defmodule NervesDesktop.Connections.ErlangSSH do
  use GenServer
  require Logger
  @behaviour NervesDesktop.Connection

  @history_limit 50_000

  @impl NervesDesktop.Connection
  def start_link(opts) do
    target = Keyword.fetch!(opts, :target)
    GenServer.start_link(__MODULE__, opts, name: via_tuple(target))
  end

  defp via_tuple(target) do
    {:via, Registry, {NervesDesktop.ConnectionRegistry, target}}
  end

  @impl NervesDesktop.Connection
  def connect(pid, target, user, password) do
    GenServer.call(pid, {:connect, target, user, password}, 10_000)
  end

  @impl NervesDesktop.Connection
  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  @impl NervesDesktop.Connection
  def send_data(pid, data) do
    GenServer.cast(pid, {:send_data, data})
  end

  @impl NervesDesktop.Connection
  def get_history(pid) do
    GenServer.call(pid, :get_history)
  end

  @impl true
  def init(opts) do
    target = Keyword.fetch!(opts, :target)
    # Store module name in Registry metadata
    Registry.update_value(NervesDesktop.ConnectionRegistry, target, fn _ -> __MODULE__ end)
    {:ok, %{conn: nil, channel: nil, target: target, history: [], history_size: 0}}
  end

  @impl true
  def handle_call({:connect, target, user, password}, _from, state) do
    Logger.info("Opening Erlang SSH connection to #{target}")

    # Convert target to charlist for :ssh
    host = String.to_charlist(target)

    opts = [
      user: String.to_charlist(user),
      silently_accept_hosts: true,
      user_interaction: false,
      connect_timeout: 5000
    ]

    opts = if password, do: [{:password, String.to_charlist(password)} | opts], else: opts

    case :ssh.connect(host, 22, opts) do
      {:ok, conn} ->
        case :ssh_connection.session_channel(conn, :infinity) do
          {:ok, channel} ->
            :ssh_connection.ptty_alloc(conn, channel, [])
            :ssh_connection.shell(conn, channel)
            {:reply, :ok, %{state | conn: conn, channel: channel, target: target, history: [], history_size: 0}}

          {:error, reason} ->
            :ssh.close(conn)
            {:reply, {:error, reason}, state}
        end

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    if state.conn, do: :ssh.close(state.conn)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, IO.iodata_to_binary(state.history), state}
  end

  @impl true
  def handle_cast({:send_data, data}, %{conn: conn, channel: channel} = state) do
    if conn && channel do
      :ssh_connection.send(conn, channel, data)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ssh_cm, conn, {:data, channel, _type, data}}, %{conn: conn, channel: channel} = state) do
    data_size = byte_size(data)
    {new_history, new_size} = 
      if state.history_size + data_size > @history_limit do
        {[data], data_size}
      else
        {state.history ++ [data], state.history_size + data_size}
      end

    broadcast_output(state.target, data)
    {:noreply, %{state | history: new_history, history_size: new_size}}
  end

  @impl true
  def handle_info({:ssh_cm, conn, {:eof, channel}}, %{conn: conn, channel: channel} = state) do
    Logger.info("Erlang SSH EOF received")
    broadcast_output(state.target, "\r\n\x1B[1;31m[SSH Session Closed]\x1B[0m\r\n")
    broadcast_closed(state.target)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:ssh_cm, conn, {:exit_status, channel, status}}, %{conn: conn, channel: channel} = state) do
    Logger.info("Erlang SSH Exit status: #{status}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:ssh_cm, conn, {:closed, channel}}, %{conn: conn, channel: channel} = state) do
    Logger.info("Erlang SSH Channel closed")
    broadcast_closed(state.target)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("ErlangSSH unhandled info: #{inspect(msg)}")
    {:noreply, state}
  end

  defp broadcast_output(target, data) do
    Phoenix.PubSub.broadcast(
      NervesDesktop.PubSub,
      "connection_output:#{target}",
      {:connection_output, target, data}
    )
  end

  defp broadcast_closed(target) do
    Phoenix.PubSub.broadcast(
      NervesDesktop.PubSub,
      "connection_output:#{target}",
      {:connection_closed, target}
    )
  end
end
