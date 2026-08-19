defmodule NervesDesktop.Connections.ErlangSSH do
  use GenServer, restart: :temporary
  require Logger
  @behaviour NervesDesktop.Connection

  alias NervesDesktop.Connection
  alias NervesDesktop.Connection.Buffer
  alias NervesDesktop.Connections.SSHError

  @impl NervesDesktop.Connection
  def start_link(opts) do
    target = Keyword.fetch!(opts, :target)
    GenServer.start_link(__MODULE__, opts, name: Connection.via_tuple(target))
  end

  @impl NervesDesktop.Connection
  def connect(pid, target, user, password) do
    GenServer.call(pid, {:connect, target, user, password}, 15_000)
  end

  @impl NervesDesktop.Connection
  def send_data(pid, data) do
    GenServer.cast(pid, {:send_data, data})
  end

  @impl NervesDesktop.Connection
  def resize(pid, cols, rows) do
    GenServer.cast(pid, {:resize, cols, rows})
  end

  @impl NervesDesktop.Connection
  def get_history(pid) do
    GenServer.call(pid, :get_history)
  end

  @impl true
  def init(opts) do
    # Trap exits so terminate/2 runs on supervisor shutdown and closes the connection
    Process.flag(:trap_exit, true)
    target = Keyword.fetch!(opts, :target)
    Connection.register_backend(target, __MODULE__)
    {:ok, %{conn: nil, channel: nil, target: target, buffer: Buffer.new(), cols: 80, rows: 24}}
  end

  @impl true
  def terminate(_reason, state) do
    if state.conn, do: :ssh.close(state.conn)
    :ok
  end

  @impl true
  def handle_call({:connect, target, user, password}, _from, state) do
    Logger.info("Opening Erlang SSH connection to #{target} (user: #{user})")

    host = String.to_charlist(target)

    opts = [
      user: String.to_charlist(user),
      silently_accept_hosts: true,
      user_interaction: false,
      connect_timeout: 5000
    ]

    opts = if password, do: [{:password, String.to_charlist(password)} | opts], else: opts

    connect_and_open_channel(host, opts, target, state, password != nil)
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, Buffer.to_binary(state.buffer), state}
  end

  defp connect_and_open_channel(host, opts, target, state, password?) do
    case :ssh.connect(host, 22, opts, 5000) do
      {:ok, conn} ->
        open_session_channel(conn, target, state)

      {:error, reason} ->
        handle_connect_error(reason, target, state, password?)
    end
  end

  defp open_session_channel(conn, target, state) do
    case :ssh_connection.session_channel(conn, 5000) do
      {:ok, channel} ->
        :ssh_connection.ptty_alloc(conn, channel, [
          {:term, ~c"xterm-256color"},
          {:width, state.cols},
          {:height, state.rows}
        ])

        :ssh_connection.shell(conn, channel)

        {:reply, :ok,
         %{state | conn: conn, channel: channel, target: target, buffer: Buffer.new()}}

      {:error, reason} ->
        Logger.error("Erlang SSH failed to open channel: #{inspect(reason)}")
        :ssh.close(conn)
        {:reply, {:error, reason}, state}
    end
  end

  defp handle_connect_error(reason, target, state, password?) do
    Logger.error("Erlang SSH failed to connect to #{target}: #{inspect(reason)}")
    {:reply, {:error, SSHError.describe(reason, target: target, password?: password?)}, state}
  end

  @impl true
  def handle_cast({:resize, cols, rows}, %{conn: conn, channel: channel} = state) do
    if conn && channel, do: :ssh_connection.window_change(conn, channel, cols, rows)
    {:noreply, %{state | cols: cols, rows: rows}}
  end

  @impl true
  def handle_cast({:send_data, data}, %{conn: conn, channel: channel} = state) do
    if conn && channel do
      :ssh_connection.send(conn, channel, data)
    end

    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:ssh_cm, conn, {:data, channel, _type, data}},
        %{conn: conn, channel: channel} = state
      ) do
    Connection.broadcast_output(state.target, data)
    {:noreply, %{state | buffer: Buffer.push(state.buffer, data)}}
  end

  @impl true
  def handle_info({:ssh_cm, conn, {:eof, channel}}, %{conn: conn, channel: channel} = state) do
    Logger.info("Erlang SSH EOF received")
    Connection.broadcast_output(state.target, "\r\n\x1B[1;31m[SSH Session Closed]\x1B[0m\r\n")
    Connection.broadcast_closed(state.target)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(
        {:ssh_cm, conn, {:exit_status, channel, status}},
        %{conn: conn, channel: channel} = state
      ) do
    Logger.info("Erlang SSH Exit status: #{status}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:ssh_cm, conn, {:closed, channel}}, %{conn: conn, channel: channel} = state) do
    Logger.info("Erlang SSH Channel closed")
    Connection.broadcast_closed(state.target)
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("ErlangSSH unhandled info: #{inspect(msg)}")
    {:noreply, state}
  end
end
