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

  @system_script "/usr/bin/script"

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

  # Apple's `script` and util-linux's `script` take incompatible argument forms,
  # and `do_build/3` picks the form from the OS. Prefer the base-system binary so
  # that a util-linux `script` earlier in PATH cannot be handed BSD-form
  # arguments, which fails with "failed to parse output limit size".
  defp resolve_script(:auto) do
    if File.regular?(@system_script),
      do: @system_script,
      else: System.find_executable("script")
  end

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
