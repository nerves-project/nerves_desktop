defmodule NervesDesktop.Firmware.Upload.ErlangSSH do
  @moduledoc """
  Uploads through the SSH client built into Erlang, so no external tools are
  needed and Windows works the same as everywhere else.

  Unlike a port, an SSH channel can be half-closed, so this signals the end of
  the archive with `send_eof/2` and then waits for the device to finish writing.
  """

  @behaviour NervesDesktop.Firmware.Upload

  alias NervesDesktop.Firmware.Upload.Progress

  @chunk 64 * 1024
  @connect_timeout 10_000
  @send_timeout 60_000
  @apply_timeout :timer.minutes(30)

  @impl true
  def upload(target, fw_path, opts \\ []) do
    with {:ok, conn} <- connect(target, opts[:password]),
         {:ok, channel} <- open_subsystem(conn) do
      try do
        stream(conn, channel, fw_path, opts[:on_progress])
      after
        :ssh.close(conn)
      end
    end
  end

  defp connect(target, password) do
    opts =
      [
        user: ~c"root",
        silently_accept_hosts: true,
        user_interaction: false,
        # Without this Erlang falls through to keyboard-interactive, which it
        # cannot answer with user_interaction off, and reports the refusal as
        # "Service not available" rather than as an authentication failure.
        auth_methods: ~c"publickey,password",
        connect_timeout: @connect_timeout
      ]
      |> then(fn opts ->
        if password, do: [{:password, String.to_charlist(password)} | opts], else: opts
      end)

    :ssh.connect(String.to_charlist(target), 22, opts, @connect_timeout)
  end

  defp open_subsystem(conn) do
    with {:ok, channel} <- :ssh_connection.session_channel(conn, @connect_timeout) do
      case :ssh_connection.subsystem(conn, channel, ~c"fwup", @connect_timeout) do
        :success -> {:ok, channel}
        :failure -> {:error, :no_fwup_subsystem}
        other -> other
      end
    end
  end

  # Progress is counted locally rather than scraped from the device. SSH
  # windowing back-pressures `send/4` when the device stops consuming, so bytes
  # accepted really do track the transfer, and every device reports it the same
  # way regardless of the fwup version it happens to be running.
  defp stream(conn, channel, fw_path, on_progress) do
    total = File.stat!(fw_path).size

    fw_path
    |> File.stream!(@chunk)
    |> Enum.reduce_while({:ok, 0}, fn chunk, {:ok, sent} ->
      case :ssh_connection.send(conn, channel, chunk, @send_timeout) do
        :ok ->
          sent = sent + byte_size(chunk)
          report(on_progress, sent, total)
          {:cont, {:ok, sent}}

        error ->
          {:halt, error}
      end
    end)
    |> case do
      {:ok, _sent} ->
        :ssh_connection.send_eof(conn, channel)
        await(conn, channel, on_progress)

      error ->
        error
    end
  end

  defp report(nil, _sent, _total), do: :ok
  defp report(_on_progress, _sent, 0), do: :ok

  # Hold back the last percent until the device has actually finished writing.
  defp report(on_progress, sent, total) do
    on_progress.(min(99, div(sent * 100, total)))
    :ok
  end

  defp await(conn, channel, on_progress) do
    receive do
      {:ssh_cm, ^conn, {:data, ^channel, _type, data}} ->
        Progress.report(data, on_progress)
        await(conn, channel, on_progress)

      {:ssh_cm, ^conn, {:exit_status, ^channel, 0}} ->
        {:ok, :applied}

      {:ssh_cm, ^conn, {:exit_status, ^channel, status}} ->
        {:error, {:exit_status, status}}

      {:ssh_cm, ^conn, {:closed, ^channel}} ->
        # The device reboots as soon as it has written, so a channel that
        # closes without a status has still done its job.
        {:ok, :applied}

      {:ssh_cm, ^conn, _other} ->
        await(conn, channel, on_progress)
    after
      @apply_timeout -> {:error, :timeout}
    end
  end
end
