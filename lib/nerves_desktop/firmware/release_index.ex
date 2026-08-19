defmodule NervesDesktop.Firmware.ReleaseIndex do
  @moduledoc """
  Tracks the newest published build of each catalog image seen on the network.

  It subscribes to discovery itself so the lookup happens once however many
  LiveViews are mounted, and so that discovery keeps working when this does
  not: a captive portal or a GitHub outage must never stop you finding a board
  on your bench.

  Results are cached because the scanner runs every ten seconds while the
  GitHub API allows sixty unauthenticated calls an hour.
  """

  use GenServer

  alias NervesDesktop.Firmware.Catalog
  alias NervesDesktop.Firmware.ReleaseFetcher

  require Logger

  @topic "releases"
  @discovery_topic "discovery"
  @fresh_for :timer.hours(6)
  @retry_after :timer.minutes(15)

  @type status :: :current | {:stale, binary()} | :unknown | :pending
  @type key :: {binary(), binary()}

  def start_link(opts \\ []) do
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  The update status of each device, keyed by device id.

  Batched deliberately: the caller asks once per device-list change rather than
  once per row per render.
  """
  @spec statuses(GenServer.server(), [map()]) :: %{binary() => status()}
  def statuses(server \\ __MODULE__, devices) do
    GenServer.call(server, {:statuses, devices})
  end

  @doc """
  Asks for any device that could be updated but has no release cached yet.
  """
  @spec ensure(GenServer.server(), [map()]) :: :ok
  def ensure(server \\ __MODULE__, devices), do: GenServer.cast(server, {:ensure, devices})

  @doc false
  def put(server \\ __MODULE__, key, release),
    do: GenServer.call(server, {:put, key, {:ok, release}})

  @doc false
  def put_failure(server \\ __MODULE__, key),
    do: GenServer.call(server, {:put, key, :unavailable})

  @doc """
  Compares a device against a release.

  Prefers the firmware UUID, which is exact and catches a rebuild at the same
  version number. Falls back to version strings when either side lacks a UUID,
  which is what happens when `fwup` is not installed to read one.
  """
  @spec compare(map(), map()) :: :current | {:stale, binary()} | :unknown
  def compare(%{uuid: device_uuid}, %{uuid: release_uuid, version: version})
      when is_binary(device_uuid) and is_binary(release_uuid) do
    if device_uuid == release_uuid, do: :current, else: {:stale, version}
  end

  def compare(%{version: device_version}, %{version: version})
      when is_binary(device_version) and is_binary(version) do
    if device_version == version, do: :current, else: {:stale, version}
  end

  def compare(_device, _release), do: :unknown

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(NervesDesktop.PubSub, @discovery_topic)
    {:ok, %{cache: %{}, inflight: MapSet.new()}}
  end

  @impl true
  def handle_call({:statuses, devices}, _from, state) do
    {:reply, Map.new(devices, &{&1[:id], status_of(&1, state)}), state}
  end

  @impl true
  def handle_call({:put, key, entry}, _from, state) do
    {:reply, :ok, cache(state, key, entry)}
  end

  @impl true
  def handle_cast({:ensure, devices}, state) do
    {:noreply, Enum.reduce(devices, state, &maybe_resolve/2)}
  end

  @impl true
  def handle_info({:devices_updated, devices}, state) do
    {:noreply, Enum.reduce(devices, state, &maybe_resolve/2)}
  end

  @impl true
  def handle_info({:resolved, key, result}, state) do
    entry =
      case result do
        {:ok, release} ->
          {:ok, release}

        {:error, reason} ->
          Logger.debug("[ReleaseIndex] #{inspect(key)} unavailable: #{inspect(reason)}")
          :unavailable
      end

    {:noreply, state |> cache(key, entry) |> Map.update!(:inflight, &MapSet.delete(&1, key))}
  end

  # Resolution runs in a task, so a slow or hanging request cannot block the
  # answers this process still owes every mounted LiveView.
  @impl true
  def handle_info({ref, _result}, state) when is_reference(ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, _pid, _reason}, state), do: {:noreply, state}

  defp status_of(device, state) do
    case key_for(device) do
      :no_match ->
        :unknown

      {:ok, key} ->
        case Map.get(state.cache, key) do
          {{:ok, release}, _at} -> compare(device, release)
          {:unavailable, _at} -> :unknown
          nil -> :pending
        end
    end
  end

  defp maybe_resolve(device, state) do
    with {:ok, key} <- key_for(device),
         false <- MapSet.member?(state.inflight, key),
         true <- stale_entry?(state.cache[key]) do
      start_resolve(device, key)
      Map.update!(state, :inflight, &MapSet.put(&1, key))
    else
      _ -> state
    end
  end

  defp start_resolve(device, {repo, target} = key) do
    parent = self()
    {:ok, _name, config} = Catalog.match(device)
    asset = Catalog.asset_name(config, target)

    Task.Supervisor.async_nolink(NervesDesktop.TaskSupervisor, fn ->
      send(parent, {:resolved, key, ReleaseFetcher.impl().resolve(repo, asset)})
    end)
  end

  defp key_for(device) do
    case Catalog.match(device) do
      {:ok, _name, config} -> {:ok, {config.repo, device[:platform]}}
      :no_match -> :no_match
    end
  end

  defp stale_entry?(nil), do: true

  defp stale_entry?({{:ok, _release}, at}),
    do: System.monotonic_time(:millisecond) - at > @fresh_for

  defp stale_entry?({:unavailable, at}),
    do: System.monotonic_time(:millisecond) - at > @retry_after

  defp cache(state, key, entry) do
    Phoenix.PubSub.broadcast(NervesDesktop.PubSub, @topic, {:release_resolved, key})
    put_in(state, [:cache, key], {entry, System.monotonic_time(:millisecond)})
  end
end
