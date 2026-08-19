defmodule NervesDesktop.Firmware.UpdateSupervisor do
  @moduledoc """
  Supervises in-flight device updates, one process per device.
  """

  use DynamicSupervisor

  alias NervesDesktop.Firmware.UpdateSession

  @registry NervesDesktop.Firmware.UpdateRegistry

  def start_link(init_arg) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: __MODULE__)
  end

  @doc """
  Starts an update, unless one is already running for that device.
  """
  @spec start_update(map(), UpdateSession.source(), keyword()) ::
          {:ok, pid()} | {:error, :already_running | term()}
  def start_update(device, source, opts \\ []) do
    spec = {UpdateSession, [device: device, source: source] ++ opts}

    case DynamicSupervisor.start_child(__MODULE__, spec) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, _pid}} -> {:error, :already_running}
      other -> other
    end
  end

  @doc """
  Stops the update running for a device, if there is one.
  """
  @spec cancel(binary()) :: :ok
  def cancel(device_id) do
    case Registry.lookup(@registry, device_id) do
      [{pid, _}] -> DynamicSupervisor.terminate_child(__MODULE__, pid)
      [] -> :ok
    end

    :ok
  end

  @impl true
  def init(_init_arg), do: DynamicSupervisor.init(strategy: :one_for_one)
end
