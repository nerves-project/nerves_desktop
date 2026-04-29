defmodule NervesDesktop.Connections.SystemSSH do
  use GenServer
  require Logger
  @behaviour NervesDesktop.Connection

  @history_limit 50_000 # 50KB

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
    GenServer.call(pid, {:connect, target, user, password})
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

    {:ok,
     %{
       status: :disconnected,
       target: target,
       port: nil,
       password: nil,
       password_sent: false,
       history: [],
       history_size: 0
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
    args = ["-q", "/dev/null", "ssh", "-tt", "-o", "StrictHostKeyChecking=no", "-o", "UserKnownHostsFile=/dev/null", "-o", "ConnectTimeout=5", connection_str]

    Logger.info("Opening interactive System SSH connection: script #{Enum.join(args, " ")}")

    port = Port.open({:spawn_executable, "/usr/bin/script"}, [:binary, :exit_status, :stderr_to_stdout, args: args])

    {:reply, :ok,
     %{
       state
       | status: :connected,
         target: target,
         port: port,
         password: password,
         password_sent: false,
         history: [],
         history_size: 0
     }}
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    if state.port, do: Port.close(state.port)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, IO.iodata_to_binary(state.history), state}
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
    # Check for password prompt using regex
    state =
      if state.password && !state.password_sent && data =~ ~r/[Pp]assword:/ do
        Logger.info("Detected password prompt, sending password...")
        Process.send_after(self(), {:send_password, state.password}, 100)
        %{state | password_sent: true}
      else
        state
      end

    # Efficient history buffering using iodata
    data_size = byte_size(data)
    {new_history, new_size} = 
      if state.history_size + data_size > @history_limit do
        # Simple truncation: clear history if it exceeds limit to avoid complex slicing
        # In a real app, a proper circular buffer or queue would be better
        {[data], data_size}
      else
        {state.history ++ [data], state.history_size + data_size}
      end

    broadcast_output(state.target, data)

    {:noreply, %{state | history: new_history, history_size: new_size}}
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
    broadcast_output(state.target, "\r\n\x1B[1;31m[SSH Session Closed]\x1B[0m\r\n")
    broadcast_closed(state.target)

    {:stop, :normal, state}
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
