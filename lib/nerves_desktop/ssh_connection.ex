defmodule NervesDesktop.SSHConnection do
  use GenServer
  require Logger

  @topic "ssh_connection"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def connect(pid, device_ip, user \\ "root") do
    GenServer.call(pid, {:connect, device_ip, user})
  end

  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  def send_data(pid, data) do
    GenServer.cast(pid, {:send_data, data})
  end

  @impl true
  def init(_opts) do
    {:ok, %{status: :disconnected, device_ip: nil, port: nil}}
  end

  @impl true
  def handle_call({:connect, device_ip, user}, _from, state) do
    if state.port, do: Port.close(state.port)

    # We use `script -q /dev/null` to trick ssh into thinking it has a TTY.
    # This allows password prompts to be sent over the pipe.
    # -tt forces pseudo-terminal allocation.
    connection_str = "#{user}@#{device_ip}"
    ssh_cmd = "ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 #{connection_str}"
    
    # macOS 'script' syntax: script -q /dev/null command
    cmd = "script -q /dev/null #{ssh_cmd}"
    
    Logger.info("Opening interactive SSH connection: #{cmd}")
    
    port = Port.open({:spawn, cmd}, [:binary, :exit_status, :stderr_to_stdout])

    {:reply, :ok, %{state | status: :connected, device_ip: device_ip, port: port}}
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    if state.port, do: Port.close(state.port)
    {:reply, :ok, %{state | status: :disconnected, device_ip: nil, port: nil}}
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
    broadcast(state.device_ip, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("SSH Port closed with status: #{status}")
    broadcast(state.device_ip, "\r\n\x1B[1;31m[SSH Session Closed]\x1B[0m\r\n")
    {:noreply, %{state | status: :disconnected, device_ip: nil, port: nil}}
  end

  defp broadcast(device_ip, message) do
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, @topic, {:ssh_output, device_ip, message})
  end
end
