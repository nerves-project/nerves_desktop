defmodule NervesDesktop.Firmware.Upload.Progress do
  @moduledoc """
  Turns the device's `fwup` output into a percentage.

  Progress is read from what the device sends back rather than from the bytes
  we have written. On wifi our socket buffer drains long before the flash is
  written, so local counting would sit at 100% while the device is still busy.

  The exact shape of that output depends on the `fwup` and `ssh_subsystem_fwup`
  versions installed on the device, so this looks for a percentage anywhere in
  the stream and reports nothing when it finds none, which leaves the caller on
  an indeterminate bar rather than a wrong number.
  """

  @percent ~r/(\d{1,3})\s*%/

  @doc """
  Calls `on_progress` with the most recent percentage in this chunk, if any.
  """
  @spec report(binary(), (non_neg_integer() -> any()) | nil) :: :ok
  def report(_data, nil), do: :ok

  def report(data, on_progress) when is_function(on_progress, 1) do
    case percent(data) do
      nil -> :ok
      value -> on_progress.(value) && :ok
    end

    :ok
  end

  @doc """
  The last percentage in a chunk of device output.
  """
  @spec percent(binary()) :: non_neg_integer() | nil
  def percent(data) when is_binary(data) do
    case List.last(Regex.scan(@percent, data)) do
      [_, value] -> value |> String.to_integer() |> min(100)
      _ -> nil
    end
  end
end
