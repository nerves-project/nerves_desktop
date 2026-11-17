defmodule NervesDesktop.SightingsTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Sightings

  @t0 ~U[2026-11-12 10:00:00Z]

  defp at(seconds), do: DateTime.add(@t0, seconds, :second)
  defp device(id), do: %{id: id}

  test "devices in the first scan were found at launch" do
    {[a], _sightings} = Sightings.stamp(Sightings.new(), [device("a")], @t0)

    assert a.first_seen_at == @t0
    assert a.found_at_launch?
  end

  test "a device that misses the first scan still counts as present at launch" do
    {_, sightings} = Sightings.stamp(Sightings.new(), [device("a")], @t0)
    {[_a, b], _} = Sightings.stamp(sightings, [device("a"), device("b")], at(20))

    assert b.first_seen_at == at(20)
    assert b.found_at_launch?
  end

  test "a device that appears later is an arrival" do
    {_, sightings} = Sightings.stamp(Sightings.new(), [device("a")], @t0)
    {[a, b], _} = Sightings.stamp(sightings, [device("a"), device("b")], at(120))

    assert a.first_seen_at == @t0
    assert b.first_seen_at == at(120)
    refute b.found_at_launch?
  end

  test "newest_first puts arrivals first, newest first, ahead of launch devices" do
    {_, sightings} = Sightings.stamp(Sightings.new(), [device("b"), device("a")], @t0)
    {_, sightings} = Sightings.stamp(sightings, [device("c")], at(60))
    {devices, _} = Sightings.stamp(sightings, [device("b"), device("c"), device("d")], at(120))

    assert devices |> Sightings.newest_first() |> Enum.map(& &1.id) == ["d", "c", "b"]

    {devices, _} =
      Sightings.stamp(sightings, [device("a"), device("b"), device("c")], at(120))

    assert devices |> Sightings.newest_first() |> Enum.map(& &1.id) == ["c", "a", "b"]
  end

  test "a device keeps its first sighting after dropping off and coming back" do
    {_, sightings} = Sightings.stamp(Sightings.new(), [device("a")], @t0)
    {_, sightings} = Sightings.stamp(sightings, [], at(60))
    {[a], _} = Sightings.stamp(sightings, [device("a")], at(120))

    assert a.first_seen_at == @t0
    assert a.found_at_launch?
  end
end
