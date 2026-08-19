defmodule NervesDesktop.Firmware do
  @moduledoc """
  Rules shared by everything that writes firmware, wherever it is headed.
  """

  @doc """
  Scales a phase's own percentage into progress across the whole job.

  Fetching the image fills the first half of the bar and writing it fills the
  second, so the number always means total progress rather than restarting at
  zero halfway through. A firmware that came from disk has nothing to fetch, so
  writing it owns the whole bar.
  """
  @spec total_percent(:downloading | :uploading | :rebooting, non_neg_integer(), boolean()) ::
          non_neg_integer()
  def total_percent(phase, percent, downloads?)

  def total_percent(:downloading, percent, _downloads?), do: halve(percent)
  def total_percent(:uploading, percent, true), do: 50 + halve(percent)
  def total_percent(:uploading, percent, false), do: clamp(percent)
  def total_percent(:rebooting, _percent, _downloads?), do: 100

  @doc """
  Where the bar sits when a phase begins and has reported nothing yet.
  """
  @spec phase_floor(:downloading | :uploading | :rebooting, boolean()) :: non_neg_integer()
  def phase_floor(phase, downloads?), do: total_percent(phase, 0, downloads?)

  defp halve(percent), do: div(clamp(percent), 2)

  defp clamp(percent) when percent < 0, do: 0
  defp clamp(percent) when percent > 100, do: 100
  defp clamp(percent), do: percent
end
