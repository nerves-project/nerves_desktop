defmodule NervesDesktop.Connections.UART do
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
  def connect(pid, target, _user, _password) do
    GenServer.call(pid, {:connect, target})
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

    {:ok, uart_pid} = Circuits.UART.start_link()
    {:ok, %{uart_pid: uart_pid, target: target, history: [], history_size: 0}}
  end

  @impl true
  def handle_call({:connect, target}, _from, state) do
    Logger.info("Opening UART connection to #{target}")

    case Circuits.UART.open(state.uart_pid, target, speed: 115_200, active: true) do
      :ok ->
        # Send a newline to trigger the remote prompt
        Circuits.UART.write(state.uart_pid, "\r\n")
        {:reply, :ok, %{state | target: target, history: [], history_size: 0}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:disconnect, _from, state) do
    Circuits.UART.close(state.uart_pid)
    {:stop, :normal, :ok, state}
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, IO.iodata_to_binary(Enum.reverse(state.history)), state}
  end

  @impl true
  def handle_cast({:send_data, data}, state) do
    Circuits.UART.write(state.uart_pid, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) when is_binary(data) do
    data_size = byte_size(data)
    {new_history, new_size} = 
      if state.history_size + data_size > @history_limit do
        {[data], data_size}
      else
        {[data | state.history], state.history_size + data_size}
      end

    broadcast_output(state.target, data)
    {:noreply, %{state | history: new_history, history_size: new_size}}
  end

  @impl true
  def handle_info({:circuits_uart, _port, {:error, reason}}, state) do
    Logger.error("UART Error on #{state.target}: #{inspect(reason)}")
    broadcast_output(state.target, "\r\n\x1B[1;31m[UART Error: #{inspect(reason)}]\x1B[0m\r\n")
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
