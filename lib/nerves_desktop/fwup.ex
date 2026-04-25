defmodule NervesDesktop.Fwup do
  require Logger

  @doc """
  Burns firmware to the specified device using System.cmd to avoid TTY requirements.
  """
  def burn(firmware_path, device_path, wifi_config \\ %{}) do
    fwup_args = ["-d", device_path, firmware_path]

    {cmd, args} =
      if requires_sudo?() do
        {"sudo", ["fwup" | fwup_args]}
      else
        {"fwup", fwup_args}
      end

    env = build_wifi_env(wifi_config)
    
    Logger.info("Running: #{cmd} #{Enum.join(args, " ")}")

    # We use into: IO.stream() or a custom collector if we want to stream output.
    # For now, let's just collect it to avoid TTY issues.
    case System.cmd(cmd, args, env: env, stderr_to_stdout: true) do
      {_output, 0} -> :ok
      {output, exit_code} -> 
        Logger.error("fwup failed with exit code #{exit_code}: #{output}")
        {:error, "fwup error #{exit_code}"}
    end
  rescue
    e -> 
      Logger.error("Failed to execute burn: #{inspect(e)}")
      {:error, e}
  end

  defp build_wifi_env(wifi_config) do
    env = []
    env = if ssid = wifi_config[:ssid], do: [{"NERVES_WIFI_SSID", ssid} | env], else: env
    env = if pass = wifi_config[:passphrase], do: [{"NERVES_WIFI_PASSPHRASE", pass} | env], else: env
    env
  end

  defp requires_sudo?() do
    case :os.type() do
      {:unix, :linux} -> true
      {:unix, :darwin} -> false
      _ -> false
    end
  end
end
