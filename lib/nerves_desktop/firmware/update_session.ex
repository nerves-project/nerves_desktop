defmodule NervesDesktop.Firmware.UpdateSession do
  @moduledoc """
  Owns one in-flight device update.

  It lives under a supervisor rather than inside the LiveView so that a
  multi-minute upload survives navigating to another page, and so a second
  update to the same device can be refused while one is running.

  Phases are broadcast on `"update:<device_id>"`, and the last one is kept so a
  LiveView mounting mid-upload can pick up where things are.
  """

  use GenServer, restart: :temporary

  alias NervesDesktop.Firmware.Catalog
  alias NervesDesktop.Firmware.Upload

  require Logger

  @registry NervesDesktop.Firmware.UpdateRegistry

  @type source :: {:catalog, binary(), map(), binary()} | {:file, Path.t()}
  @type phase :: :downloading | :uploading | :rebooting | :failed
  @type progress :: %{phase: phase(), percent: non_neg_integer() | nil, error: term() | nil}

  def start_link(opts) do
    device = Keyword.fetch!(opts, :device)
    GenServer.start_link(__MODULE__, opts, name: via(device[:id]))
  end

  @doc """
  The latest progress for a device, or `nil` when nothing is running.
  """
  @spec progress(binary()) :: progress() | nil
  def progress(device_id) do
    case Registry.lookup(@registry, device_id) do
      [{pid, _}] -> GenServer.call(pid, :progress)
      [] -> nil
    end
  end

  @doc """
  Progress for every running update, keyed by device id.
  """
  @spec active() :: %{binary() => progress()}
  def active do
    @registry
    |> Registry.select([{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Map.new(fn {device_id, pid} -> {device_id, GenServer.call(pid, :progress)} end)
  end

  defp via(device_id), do: {:via, Registry, {@registry, device_id}}

  @impl true
  def init(opts) do
    state = %{
      device: Keyword.fetch!(opts, :device),
      source: Keyword.fetch!(opts, :source),
      password: Keyword.get(opts, :password),
      backend: Keyword.get(opts, :backend) || Upload.backend(),
      downloader: Keyword.get(opts, :downloader, NervesBurner.Downloader),
      progress: %{phase: starting_phase(Keyword.fetch!(opts, :source)), percent: nil, error: nil},
      task: nil
    }

    {:ok, state, {:continue, :run}}
  end

  defp starting_phase({:catalog, _, _, _}), do: :downloading
  defp starting_phase({:file, _}), do: :uploading

  @impl true
  def handle_continue(:run, state) do
    parent = self()

    task =
      Task.Supervisor.async_nolink(NervesDesktop.TaskSupervisor, fn ->
        run(parent, state)
      end)

    {:noreply, %{state | task: task.ref} |> announce()}
  end

  @impl true
  def handle_call(:progress, _from, state), do: {:reply, state.progress, state}

  @impl true
  def handle_info({:phase, phase}, state) do
    {:noreply, state |> put_progress(%{phase: phase, percent: nil, error: nil}) |> announce()}
  end

  @impl true
  def handle_info({:percent, percent}, state) do
    {:noreply, state |> put_progress(%{state.progress | percent: percent}) |> announce()}
  end

  @impl true
  def handle_info({ref, result}, %{task: ref} = state) do
    Process.demonitor(ref, [:flush])

    case result do
      {:ok, :applied} ->
        {:stop, :normal,
         state |> put_progress(%{phase: :rebooting, percent: 100, error: nil}) |> announce()}

      {:error, reason} ->
        {:stop, :normal, state |> fail(reason) |> announce()}
    end
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, %{task: ref} = state) do
    {:stop, :normal, state |> fail(reason) |> announce()}
  end

  @impl true
  def handle_info(_message, state), do: {:noreply, state}

  defp put_progress(state, progress), do: %{state | progress: progress}

  defp fail(state, reason) do
    Logger.warning("[Update] #{state.device[:id]} failed: #{inspect(reason)}")
    put_progress(state, %{phase: :failed, percent: nil, error: reason})
  end

  defp announce(state) do
    Phoenix.PubSub.broadcast(
      NervesDesktop.PubSub,
      "update:#{state.device[:id]}",
      {:update_progress, state.device[:id], state.progress}
    )

    state
  end

  defp run(parent, %{source: {:file, path}} = state) do
    upload(parent, state, path)
  end

  defp run(parent, %{source: {:catalog, _name, config, target}} = state) do
    send(parent, {:phase, :downloading})

    result =
      state.downloader.download(config, target,
        on_progress: fn total, current ->
          if total > 0, do: send(parent, {:percent, round(current / total * 100)})
        end
      )

    case result do
      {:ok, path} -> upload(parent, state, path)
      {:error, reason} -> {:error, reason}
    end
  end

  defp upload(parent, state, path) do
    send(parent, {:phase, :uploading})

    attempt(parent, state, path, state.password || published_password(state))
  end

  defp attempt(parent, state, path, password) do
    state.backend.upload(state.device[:target], path,
      password: password,
      on_progress: &send(parent, {:percent, &1})
    )
  end

  # A published image has a documented login, so offer it from the start. The
  # SSH client still tries keys first, so a device that does authorize a key
  # never sees the password, and this avoids a failed connection just to learn
  # something already known. Firmware chosen from disk is somebody's own build
  # and gets no guess.
  defp published_password(%{source: {:catalog, _name, config, _target}}),
    do: Catalog.default_password(config)

  defp published_password(_state), do: nil
end
