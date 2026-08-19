defmodule NervesDesktop.Connections.SystemSSH do
  @moduledoc """
  SSH via the host `ssh` binary. The remote PTY is fixed at 80x24 because
  `script` sizes it from the BEAM's stdin, which is not a TTY.
  """
  use GenServer, restart: :temporary
  require Logger
  @behaviour NervesDesktop.Connection

  alias NervesDesktop.Connection
  alias NervesDesktop.Connection.Buffer

  @impl NervesDesktop.Connection
  def start_link(opts) do
    target = Keyword.fetch!(opts, :target)
    GenServer.start_link(__MODULE__, opts, name: Connection.via_tuple(target))
  end

  @impl NervesDesktop.Connection
  def connect(pid, target, user, password) do
    GenServer.call(pid, {:connect, target, user, password})
  end

  @impl NervesDesktop.Connection
  def send_data(pid, data) do
    GenServer.cast(pid, {:send_data, data})
  end

  @impl NervesDesktop.Connection
  def resize(_pid, _cols, _rows), do: :ok

  @impl NervesDesktop.Connection
  def get_history(pid) do
    GenServer.call(pid, :get_history)
  end

  @impl true
  def init(opts) do
    target = Keyword.fetch!(opts, :target)
    Connection.register_backend(target, __MODULE__)

    {:ok,
     %{
       status: :disconnected,
       target: target,
       port: nil,
       password: nil,
       password_sent: false,
       buffer: Buffer.new()
     }}
  end

  @impl true
  def handle_call({:connect, target, user, password}, _from, state) do
    if state.port, do: Port.close(state.port)

    connection_str = "#{user}@#{target}"

    # Use a list of arguments to avoid shell interpolation/injection
    # 'script -q /dev/null' fakes a TTY
    # On macOS 'script' args are different than Linux. 
    # This approach is safer than string interpolation.
    args = [
      "-q",
      "/dev/null",
      "ssh",
      "-tt",
      "-o",
      "StrictHostKeyChecking=no",
      "-o",
      "UserKnownHostsFile=/dev/null",
      "-o",
      "ConnectTimeout=5",
      "-o",
      "SendEnv=LANG",
      "-o",
      "SendEnv=LC_ALL",
      connection_str
    ]

    env = NervesDesktop.HostInfo.utf8_env()

    Logger.info("Opening interactive System SSH connection: script #{Enum.join(args, " ")}")

    port =
      Port.open({:spawn_executable, "/usr/bin/script"}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args,
        env: env
      ])

    {:reply, :ok,
     %{
       state
       | status: :connected,
         target: target,
         port: port,
         password: password,
         password_sent: false,
         buffer: Buffer.new()
     }}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, Buffer.to_binary(state.buffer), state}
  end

  @impl true
  def handle_cast({:send_data, data}, %{port: port} = state) when not is_nil(port) do
    Port.command(port, data)
    {:noreply, state}
  end

  @impl true
  def handle_cast({:send_data, _data}, state) do
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    state =
      if state.password && !state.password_sent && data =~ ~r/[Pp]assword:/ do
        Logger.info("Detected auth prompt, responding")
        Process.send_after(self(), {:send_password, state.password}, 100)
        %{state | password_sent: true}
      else
        state
      end

    Connection.broadcast_output(state.target, data)

    {:noreply, %{state | buffer: Buffer.push(state.buffer, data)}}
  end

  @impl true
  def handle_info({:send_password, password}, %{port: port} = state) when not is_nil(port) do
    Port.command(port, password <> "\n")
    # Clear password from state after sending for security
    {:noreply, %{state | password: nil}}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("System SSH Port closed with status: #{status}")
    Connection.broadcast_output(state.target, "\r\n\x1B[1;31m[SSH Session Closed]\x1B[0m\r\n")
    Connection.broadcast_closed(state.target)

    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:send_password, _password}, state) do
    Logger.debug("SystemSSH dropped a deferred credential send with no open port")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("SystemSSH unhandled info: #{inspect(msg)}")
    {:noreply, state}
  end
end
