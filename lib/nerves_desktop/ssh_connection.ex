defmodule NervesDesktop.SSHConnection do
  use GenServer
  require Logger

  @topic "ssh_connection"

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  def connect(pid, device_ip, user \\ "root", password \\ nil) do
    GenServer.call(pid, {:connect, device_ip, user, password})
  end

  def disconnect(pid) do
    GenServer.call(pid, :disconnect)
  end

  def send_data(pid, data) do
    GenServer.cast(pid, {:send_data, data})
  end

  @impl true
  def init(_opts) do
    {:ok,
     %{status: :disconnected, device_ip: nil, port: nil, password: nil, password_sent: false}}
  end

  @impl true
  def handle_call({:connect, device_ip, user, password}, _from, state) do
    if state.port, do: Port.close(state.port)

    connection_str = "#{user}@#{device_ip}"

    ssh_cmd =
      "ssh -tt -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=5 #{connection_str}"

    cmd = "script -q /dev/null #{ssh_cmd}"

    Logger.info("Opening interactive SSH connection: #{cmd}")

    port = Port.open({:spawn, cmd}, [:binary, :exit_status, :stderr_to_stdout])

    {:reply, :ok,
     %{
       state
       | status: :connected,
         device_ip: device_ip,
         port: port,
         password: password,
         password_sent: false
     }}
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    if state.port, do: Port.close(state.port)

    {:reply, :ok,
     %{
       state
       | status: :disconnected,
         device_ip: nil,
         port: nil,
         password: nil,
         password_sent: false
     }}
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
    # Check for password prompt if we have a password to send and haven't sent it yet
    state =
      if state.password && !state.password_sent && String.contains?(data, "Password:") do
        Logger.info("Detected password prompt, sending password...")
        # Small delay ensures the remote side is ready to read the password
        Process.send_after(self(), {:send_password, state.password}, 100)
        %{state | password_sent: true}
      else
        state
      end

    broadcast_output(state.device_ip, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({:send_password, password}, %{port: port} = state) when not is_nil(port) do
    Port.command(port, password <> "\n")
    {:noreply, state}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{port: port} = state) do
    Logger.info("SSH Port closed with status: #{status}")
    broadcast_output(state.device_ip, "\r\n\x1B[1;31m[SSH Session Closed]\x1B[0m\r\n")
    broadcast_closed(state.device_ip)

    {:noreply,
     %{
       state
       | status: :disconnected,
         device_ip: nil,
         port: nil,
         password: nil,
         password_sent: false
     }}
  end

  defp broadcast_output(device_ip, data) do
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, @topic, {:ssh_output, device_ip, data})
  end

  defp broadcast_closed(device_ip) do
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, @topic, {:ssh_closed, device_ip})
  end
end
