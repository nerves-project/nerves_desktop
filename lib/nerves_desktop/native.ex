defmodule NervesDesktop.Native do
  @moduledoc """
  Talks to the Tauri shell, and stays quiet when there is no shell to talk to.

  ElixirKit only starts its pubsub when Tauri launches the app and sets
  `ELIXIRKIT_PUBSUB`. Started any other way the supervisor is told to `:ignore`
  the child, so the registry behind it is never created and
  `ElixirKit.PubSub.subscribe/1` raises `unknown registry`. Routing every call
  to the native side through here lets a plain `mix phx.server` run degrade to a
  no-op instead of taking the LiveView down with it.
  """

  @server ElixirKit.PubSub

  @doc """
  Whether the Tauri shell is running alongside this app.
  """
  @spec available?() :: boolean()
  def available?, do: is_pid(Process.whereis(@server))

  @doc """
  Subscribes the caller to a topic from the native side, if there is one.
  """
  @spec subscribe(binary()) :: :ok
  def subscribe(topic) when is_binary(topic) do
    if available?(), do: @server.subscribe(topic)
    :ok
  end

  @doc """
  Sends a message to the native side, if there is one.
  """
  @spec broadcast(binary(), binary()) :: :ok
  def broadcast(topic, message) when is_binary(topic) and is_binary(message) do
    if available?(), do: @server.broadcast(topic, message)
    :ok
  end
end
