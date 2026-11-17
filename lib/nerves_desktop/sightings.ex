defmodule NervesDesktop.Sightings do
  @moduledoc """
  Remembers when this session first saw each device, so a device that just
  arrived can be told apart from the ones that were already there.
  """

  # A device can miss the first scan or two, so anything found this soon after
  # the first scan counts as already present.
  @launch_grace :timer.seconds(30)

  defstruct started_at: nil, first_seen: %{}

  @type t :: %__MODULE__{
          started_at: DateTime.t() | nil,
          first_seen: %{String.t() => DateTime.t()}
        }

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc """
  Adds `:first_seen_at` and `:found_at_launch?` to each device.
  """
  @spec stamp(t(), [map()], DateTime.t()) :: {[map()], t()}
  def stamp(%__MODULE__{} = sightings, devices, now \\ DateTime.utc_now()) do
    started_at = sightings.started_at || now
    first_seen = Enum.reduce(devices, sightings.first_seen, &Map.put_new(&2, &1.id, now))

    stamped =
      Enum.map(devices, fn device ->
        seen_at = Map.fetch!(first_seen, device.id)

        Map.merge(device, %{
          first_seen_at: seen_at,
          found_at_launch?: DateTime.diff(seen_at, started_at, :millisecond) <= @launch_grace
        })
      end)

    {stamped, %{sightings | started_at: started_at, first_seen: first_seen}}
  end

  @doc """
  Puts arrivals first, newest first, ahead of the devices found at launch,
  which keep their order.
  """
  @spec newest_first([map()]) :: [map()]
  def newest_first(devices) do
    {launch, arrivals} = Enum.split_with(devices, & &1.found_at_launch?)
    Enum.sort_by(arrivals, & &1.first_seen_at, {:desc, DateTime}) ++ launch
  end
end
