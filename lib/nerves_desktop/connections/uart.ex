defmodule NervesDesktop.Connections.UART do
  @moduledoc """
  A serial console. While the device has an MCP server running, that server
  holds the port, so the console goes through it and switches over whenever
  the server is started or stopped.
  """

  use GenServer, restart: :temporary
  require Logger
  @behaviour NervesDesktop.Connection

  alias NervesDesktop.Connection
  alias NervesDesktop.Connection.Buffer
  alias NervesDesktop.MCP

  @attach_retry 200

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
  def resize(_pid, _cols, _rows), do: :ok

  @impl NervesDesktop.Connection
  def get_history(pid) do
    GenServer.call(pid, :get_history)
  end

  @impl true
  def init(opts) do
    target = Keyword.fetch!(opts, :target)
    Connection.register_backend(target, __MODULE__)
    Phoenix.PubSub.subscribe(NervesDesktop.PubSub, MCP.topic())

    {:ok, uart_pid} = Circuits.UART.start_link()
    {:ok, %{uart_pid: uart_pid, target: target, buffer: Buffer.new(), link: :closed}}
  end

  @impl true
  def handle_call({:connect, target}, _from, state) do
    state = %{close(state) | target: target, buffer: Buffer.new()}

    if NervesMCP.server(target) do
      Logger.info("Opening UART connection to #{target} through its MCP server")
      {:reply, :ok, state |> attach() |> write("\r\n")}
    else
      Logger.info("Opening UART connection to #{target}")

      case open(state) do
        {:ok, state} -> {:reply, :ok, write(state, "\r\n")}
        {:error, reason} -> {:reply, {:error, reason}, state}
      end
    end
  end

  @impl true
  def handle_call(:get_history, _from, state) do
    {:reply, Buffer.to_binary(state.buffer), state}
  end

  @impl true
  def handle_cast({:send_data, data}, state) do
    {:noreply, write(state, data)}
  end

  @impl true
  def handle_info({:circuits_uart, _port, data}, state) when is_binary(data) do
    {:noreply, output(state, data)}
  end

  @impl true
  def handle_info({:circuits_uart, _port, {:error, reason}}, state) do
    Logger.error("UART Error on #{state.target}: #{inspect(reason)}")
    {:stop, :normal, failed(state, reason)}
  end

  @impl true
  def handle_info({:console_data, data}, state) do
    {:noreply, output(state, data)}
  end

  @impl true
  def handle_info({:mcp_changed, servers}, state) do
    case {state.link, Map.has_key?(servers, state.target)} do
      {:direct, true} ->
        state =
          state |> close() |> notice("The MCP server now holds this port, continuing through it")

        {:noreply, attach(state)}

      {{:proxy, _ref}, false} ->
        reopen(state)

      _unchanged ->
        {:noreply, state}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{link: {:proxy, ref}} = state) do
    {:noreply, attach(%{state | link: {:proxy, nil}})}
  end

  @impl true
  def handle_info(:attach, %{link: {:proxy, nil}} = state) do
    {:noreply, attach(state)}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.debug("UART unhandled info: #{inspect(msg)}")
    {:noreply, state}
  end

  defp open(state) do
    with :ok <- Circuits.UART.open(state.uart_pid, state.target, speed: 115_200, active: true) do
      {:ok, %{state | link: :direct}}
    end
  end

  defp reopen(state) do
    case open(close(state)) do
      {:ok, state} ->
        {:noreply, notice(state, "The MCP server stopped, the console holds this port again")}

      {:error, reason} ->
        {:stop, :normal, failed(state, reason)}
    end
  end

  # The server's connection is restarted if it fails, so keep looking for it.
  defp attach(state) do
    worker = NervesMCP.Connection.whereis(state.target)

    if worker && attached?(state.target) do
      %{state | link: {:proxy, Process.monitor(worker)}}
    else
      Process.send_after(self(), :attach, @attach_retry)
      %{state | link: {:proxy, nil}}
    end
  end

  defp attached?(target) do
    NervesMCP.Connection.attach_console(target, self()) == :ok
  catch
    :exit, _reason -> false
  end

  defp close(%{link: {:proxy, ref}} = state) do
    if ref, do: Process.demonitor(ref, [:flush])
    %{state | link: :closed}
  end

  defp close(state) do
    Circuits.UART.close(state.uart_pid)
    %{state | link: :closed}
  end

  defp write(%{link: :direct} = state, data) do
    Circuits.UART.write(state.uart_pid, data)
    state
  end

  defp write(%{link: {:proxy, _ref}} = state, data) do
    NervesMCP.Connection.send_raw(state.target, data)
    state
  end

  defp write(state, _data), do: state

  defp output(state, data) do
    Connection.broadcast_output(state.target, data)
    %{state | buffer: Buffer.push(state.buffer, data)}
  end

  defp notice(state, text), do: output(state, "\r\n\x1B[90m[#{text}]\x1B[0m\r\n")

  defp failed(state, reason) do
    state = output(state, "\r\n\x1B[1;31m[UART Error: #{inspect(reason)}]\x1B[0m\r\n")
    Connection.broadcast_closed(state.target)
    state
  end
end
