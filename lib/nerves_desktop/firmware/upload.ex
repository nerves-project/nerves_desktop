defmodule NervesDesktop.Firmware.Upload do
  @moduledoc """
  Streams a firmware archive into a device's `fwup` SSH subsystem.

  This is the same thing as `cat firmware.fw | ssh -s nerves.local fwup`, which
  is how a Nerves device is updated over the air by hand. The device writes to
  whichever half of its A/B partition pair is not running, so an interrupted
  upload leaves the running system untouched.

  Unlike the console there is no pseudo-terminal here: this is a raw byte
  stream, not an interactive session.
  """

  @type target :: binary()
  @type opts :: [on_progress: (non_neg_integer() -> any()), password: binary() | nil]

  @callback upload(target(), Path.t(), opts()) :: {:ok, :applied} | {:error, term()}

  @doc """
  The backend matching the SSH client chosen in Settings.
  """
  @spec backend() :: module()
  def backend do
    case Application.get_env(:nerves_desktop, :ssh_client, :erlang_ssh) do
      :system_ssh -> __MODULE__.SystemSSH
      _ -> __MODULE__.ErlangSSH
    end
  end
end
