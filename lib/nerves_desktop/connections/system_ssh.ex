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
  alias NervesDesktop.Connections.PasswordPrompt
  alias NervesDesktop.Connections.SSHError
  alias NervesDesktop.Connections.SystemSSH.Command

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
       prompt: PasswordPrompt.new(),
       buffer: Buffer.new()
     }}
  end

  @impl true
  def handle_call({:connect, target, user, password}, _from, state) do
    if state.port, do: Port.close(state.port)

    case Command.build(:os.type(), "#{user}@#{target}") do
      {:ok, executable, args} ->
        Logger.info("Opening interactive System SSH connection to #{target}")

        port =
          Port.open({:spawn_executable, executable}, [
            :binary,
            :exit_status,
            :stderr_to_stdout,
            args: args,
            env: NervesDesktop.HostInfo.utf8_env()
          ])

        {:reply, :ok,
         %{
           state
           | status: :connected,
             target: target,
             port: port,
             password: password,
             prompt: PasswordPrompt.new(),
             buffer: Buffer.new()
         }}

      {:error, reason} ->
        Logger.error("System SSH unavailable on this host: #{inspect(reason)}")
        {:reply, {:error, SSHError.describe(reason, target: target)}, state}
    end
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
    {action, prompt} = PasswordPrompt.feed(state.prompt, data)

    if action == :send and state.password do
      Logger.info("Detected auth prompt, responding")
      Process.send_after(self(), :send_password, 100)
    end

    Connection.broadcast_output(state.target, data)

    {:noreply, %{state | prompt: prompt, buffer: Buffer.push(state.buffer, data)}}
  end

  @impl true
  def handle_info(:send_password, %{port: port, password: password} = state)
      when not is_nil(port) and not is_nil(password) do
    Port.command(port, password <> "\n")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("System SSH Port closed with status: #{status}")
    Connection.broadcast_output(state.target, "\r\n\x1B[1;31m[SSH Session Closed]\x1B[0m\r\n")
    Connection.broadcast_closed(state.target)

    {:stop, :normal, state}
  end

  @impl true
  def handle_info(:send_password, state) do
    Logger.debug("SystemSSH dropped a deferred credential send with no open port")
    {:noreply, state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("SystemSSH unhandled info: #{inspect(msg)}")
    {:noreply, state}
  end
end
