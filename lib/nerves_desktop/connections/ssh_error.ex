defmodule NervesDesktop.Connections.SSHError do
  @moduledoc """
  Turns `:ssh.connect/4` failures into messages that say what to do next.

  Erlang reports the same reason for several distinct causes, so the message
  also depends on whether a password was supplied.
  """

  @auth_failed ~c"Unable to connect using the available authentication methods"

  # Returned for a rejected key, an unknown user, or a server that declines the session
  @refused ~c"Service not available"

  @doc """
  Whether a failure is the device declining our credentials, which is the one
  case a password can still rescue.
  """
  @spec auth_failure?(term()) :: boolean()
  def auth_failure?(reason) when reason in [@auth_failed, @refused], do: true
  def auth_failure?(_reason), do: false

  @spec describe(term(), keyword()) :: binary()
  def describe(reason, opts \\ []) do
    target = Keyword.get(opts, :target, "the device")
    password? = Keyword.get(opts, :password?, false)
    do_describe(reason, target, password?)
  end

  defp do_describe(:nxdomain, target, _password?) do
    "Can't find #{target} on the network. Check the device is powered on and connected."
  end

  defp do_describe(:econnrefused, target, _password?) do
    "#{target} refused the connection. Check SSH is enabled on the device."
  end

  defp do_describe(reason, target, _password?)
       when reason in [:etimedout, :timeout, :ehostunreach, :enetunreach] do
    "Timed out connecting to #{target}. Check the device is reachable on this network."
  end

  defp do_describe(reason, target, false) when reason in [@auth_failed, @refused] do
    "Couldn't authenticate with #{target}. Enter the device password and connect again, " <>
      "or switch to System SSH in Settings to use ssh-agent or a passphrase-protected key."
  end

  defp do_describe(@auth_failed, target, true) do
    "#{target} rejected the password."
  end

  defp do_describe(@refused, target, true) do
    "#{target} refused the connection. Check the username and that the device allows password logins."
  end

  defp do_describe(:script_not_found, _target, _password?) do
    "System SSH needs the `script` command, which isn't installed on this computer. " <>
      "Switch to Erlang SSH in Settings."
  end

  defp do_describe(:unsupported_os, _target, _password?) do
    "System SSH isn't available on this platform. Switch to Erlang SSH in Settings."
  end

  defp do_describe(:invalid_target, target, _password?) do
    "#{target} isn't a valid device address."
  end

  defp do_describe(reason, target, _password?) do
    "Couldn't connect to #{target}: #{format(reason)}"
  end

  defp format(reason) when is_list(reason), do: List.to_string(reason)
  defp format(reason) when is_binary(reason), do: reason
  defp format(reason), do: inspect(reason)
end
