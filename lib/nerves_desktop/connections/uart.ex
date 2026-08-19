defmodule NervesDesktop.Connections.UART do
  use GenServer
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
  def connect(pid, target, _user, _password) do
    GenServer.call(pid, {:connect, target})
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
    Connection.register_backend(target, __MODULE__)

    {:ok, uart_pid} = Circuits.UART.start_link()
    {:ok, %{uart_pid: uart_pid, target: target, buffer: Buffer.new()}}
  end

  @impl true
  def handle_call({:connect, target}, _from, state) do
    Logger.info("Opening UART connection to #{target}")

    case Circuits.UART.open(state.uart_pid, target, speed: 115_200, active: true) do
      :ok ->
        # Send a newline to trigger the remote prompt
        Circuits.UART.write(state.uart_pid, "\r\n")
        {:reply, :ok, %{state | target: target, buffer: Buffer.new()}}

      {:error, reason} ->
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, Buffer.to_binary(state.buffer), state}
  end

  @impl true
  def handle_cast({:send_data, data}, state) do
    Circuits.UART.write(state.uart_pid, data)
    {:noreply, state}
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) when is_binary(data) do
    Connection.broadcast_output(state.target, data)
    {:noreply, %{state | buffer: Buffer.push(state.buffer, data)}}
  end

  @impl true
  def handle_info({:circuits_uart, _port, {:error, reason}}, state) do
    Logger.error("UART Error on #{state.target}: #{inspect(reason)}")

    Connection.broadcast_output(
      state.target,
      "\r\n\x1B[1;31m[UART Error: #{inspect(reason)}]\x1B[0m\r\n"
    )

    Connection.broadcast_closed(state.target)
    {:stop, :normal, state}
  end
end
