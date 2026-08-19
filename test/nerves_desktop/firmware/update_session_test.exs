defmodule NervesDesktop.Firmware.UpdateSessionTest do
  use ExUnit.Case, async: false

  alias NervesDesktop.Firmware.UpdateSession
  alias NervesDesktop.Firmware.UpdateSupervisor

  defmodule StubUpload do
    @behaviour NervesDesktop.Firmware.Upload

    @impl true
    def upload(_target, path, opts) do
      opts[:on_progress].(50)
      send(:update_test, {:uploaded, path, self()})

      receive do
        {:reply, result} -> result
      after
        2_000 -> {:error, :stub_never_answered}
      end
    end
  end

  setup do
    Process.register(self(), :update_test)
    device = %{id: "network:pi-#{System.unique_integer([:positive])}", target: "pi.local"}

    Phoenix.PubSub.subscribe(NervesDesktop.PubSub, "update:#{device.id}")
    on_exit(fn -> UpdateSupervisor.cancel(device.id) end)

    %{device: device}
  end

  defp start(device, source \\ {:file, "/tmp/a.fw"}) do
    UpdateSupervisor.start_update(device, source, backend: StubUpload)
  end

  test "a file update starts by uploading, with nothing to download", %{device: device} do
    {:ok, _pid} = start(device)

    assert_receive {:update_progress, _id, %{phase: :uploading}}, 2_000
  end

  test "reports the backend's progress and ends in rebooting", %{device: device} do
    {:ok, _pid} = start(device)

    assert_receive {:uploaded, "/tmp/a.fw", stub}, 2_000
    assert_receive {:update_progress, _id, %{percent: 50}}, 2_000

    send(stub, {:reply, {:ok, :applied}})
    assert_receive {:update_progress, _id, %{phase: :rebooting, percent: 100}}, 2_000
  end

  test "a failed upload carries the reason through to the UI", %{device: device} do
    {:ok, _pid} = start(device)

    assert_receive {:uploaded, _, stub}, 2_000
    send(stub, {:reply, {:error, :no_fwup_subsystem}})

    assert_receive {:update_progress, _id, %{phase: :failed, error: :no_fwup_subsystem}}, 2_000
  end

  test "refuses a second update to the same device", %{device: device} do
    {:ok, _pid} = start(device)
    assert_receive {:uploaded, _, _}, 2_000

    assert start(device) == {:error, :already_running}
  end

  test "a different device can update at the same time", %{device: device} do
    other = %{id: "network:other-#{System.unique_integer([:positive])}", target: "other.local"}
    on_exit(fn -> UpdateSupervisor.cancel(other.id) end)

    {:ok, _} = start(device)
    assert {:ok, _} = start(other)
  end

  test "active/0 lets a remounting LiveView find updates already in flight", %{device: device} do
    {:ok, _pid} = start(device)
    assert_receive {:uploaded, _, _}, 2_000

    assert %{phase: :uploading} = Map.fetch!(UpdateSession.active(), device.id)
  end

  test "progress/1 is nil for a device with nothing running" do
    assert UpdateSession.progress("network:nothing-here") == nil
  end
end
