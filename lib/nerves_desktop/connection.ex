defmodule NervesDesktop.Connection do
  @moduledoc """
  Defines the behavior for connection backends (System SSH, Erlang SSH, UART).
  """

  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  @callback connect(pid :: pid(), target :: binary(), user :: binary(), password :: binary() | nil) :: :ok | {:error, term()}
  @callback disconnect(pid :: pid()) :: :ok | {:error, term()}
  @callback send_data(pid :: pid(), data :: binary()) :: :ok
  @callback get_history(pid :: pid()) :: binary()
end
