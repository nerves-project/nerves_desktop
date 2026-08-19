defmodule NervesDesktop.Connections.SystemSSH.Command do
  @moduledoc """
  Builds the PTY-wrapped `ssh` command line for the host OS.
  """

  @ssh_opts [
    "-tt",
    "-o",
    "StrictHostKeyChecking=no",
    "-o",
    "UserKnownHostsFile=/dev/null",
    "-o",
    "ConnectTimeout=5",
    "-o",
    "SendEnv=LANG",
    "-o",
    "SendEnv=LC_ALL"
  ]

  @bsd [:darwin, :freebsd, :openbsd, :netbsd]

  # The linux form runs through `sh -c`, so the target must not contain shell metacharacters
  @target ~r/\A[A-Za-z0-9._\-]+@[A-Za-z0-9._\-]+\z/

  @spec build(:os.type(), binary(), binary() | nil | :auto) ::
          {:ok, binary(), [binary()]} | {:error, atom()}
  def build(os_type, connection_str, script_path \\ :auto)

  def build(os_type, connection_str, script_path) when is_binary(connection_str) do
    if Regex.match?(@target, connection_str) do
      do_build(os_type, connection_str, resolve_script(script_path))
    else
      {:error, :invalid_target}
    end
  end

  def build(_os_type, _connection_str, _script_path), do: {:error, :invalid_target}

  defp resolve_script(:auto), do: System.find_executable("script")
  defp resolve_script(path), do: path

  defp do_build({:unix, _}, _connection_str, nil), do: {:error, :script_not_found}

  defp do_build({:unix, flavour}, connection_str, script) when flavour in @bsd do
    {:ok, script, ["-q", "/dev/null", "ssh"] ++ @ssh_opts ++ [connection_str]}
  end

  defp do_build({:unix, _}, connection_str, script) do
    command = Enum.join(["ssh"] ++ @ssh_opts ++ [connection_str], " ")
    {:ok, script, ["-q", "-c", command, "/dev/null"]}
  end

  defp do_build(_os_type, _connection_str, _script), do: {:error, :unsupported_os}
end
