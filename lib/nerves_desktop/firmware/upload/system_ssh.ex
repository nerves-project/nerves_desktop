defmodule NervesDesktop.Firmware.Upload.SystemSSH do
  @moduledoc """
  Uploads through the `ssh` binary already installed on this machine, so keys,
  ssh-agent and `~/.ssh/config` behave exactly as they do at a prompt.

  An Erlang port cannot half-close stdin, so there is no way to say "the file
  is sent, now read your side" without also killing `ssh`. EOF is therefore
  delegated to `cat`, which is what the equivalent shell pipeline does anyway.
  """

  @behaviour NervesDesktop.Firmware.Upload

  alias NervesDesktop.Firmware.Upload.Progress

  require Logger

  @ssh_opts "-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=10"

  @impl true
  def upload(target, fw_path, opts \\ []) do
    case build(target, fw_path) do
      {:ok, exe, args} -> run(exe, args, opts)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Builds the command without running it.

  The archive path and the host are passed as arguments rather than spliced
  into the script, so `sh` binds them to `$0` and `$1` and neither can alter
  the command.
  """
  @spec build(binary(), Path.t(), binary() | nil | :auto) ::
          {:ok, binary(), [binary()]} | {:error, :ssh_not_found}
  def build(target, fw_path, ssh \\ :auto)

  def build(target, fw_path, :auto), do: build(target, fw_path, System.find_executable("ssh"))

  def build(_target, _fw_path, nil), do: {:error, :ssh_not_found}

  def build(target, fw_path, ssh) do
    script = ~s(cat "$0" | "#{ssh}" #{@ssh_opts} -s "$1" fwup)
    {:ok, "/bin/sh", ["-c", script, fw_path, "root@#{target}"]}
  end

  defp run(exe, args, opts) do
    port =
      Port.open({:spawn_executable, exe}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        args: args
      ])

    collect(port, opts[:on_progress])
  end

  defp collect(port, on_progress) do
    receive do
      {^port, {:data, data}} ->
        Progress.report(data, on_progress)
        collect(port, on_progress)

      {^port, {:exit_status, 0}} ->
        {:ok, :applied}

      {^port, {:exit_status, status}} ->
        {:error, {:exit_status, status}}
    after
      :timer.minutes(30) -> {:error, :timeout}
    end
  end
end
