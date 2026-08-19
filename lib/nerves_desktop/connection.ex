defmodule NervesDesktop.Connection do
  @moduledoc """
  Behaviour and shared helpers for connection backends (System SSH, Erlang SSH, UART).
  """

  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  @callback connect(pid(), target :: binary(), user :: binary(), password :: binary() | nil) ::
              :ok | {:error, term()}
  @callback send_data(pid(), data :: binary()) :: :ok
  @callback get_history(pid()) :: binary()

  def via_tuple(target), do: {:via, Registry, {NervesDesktop.ConnectionRegistry, target}}

  def register_backend(target, module) do
    Registry.update_value(NervesDesktop.ConnectionRegistry, target, fn _ -> module end)
  end

  def topic(target), do: "connection_output:#{target}"

  def broadcast_output(target, data) do
    Phoenix.PubSub.broadcast(
      NervesDesktop.PubSub,
      topic(target),
      {:connection_output, target, data}
    )
  end

  def broadcast_closed(target) do
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, topic(target), {:connection_closed, target})
  end
end
