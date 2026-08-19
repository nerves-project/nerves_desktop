defmodule NervesDesktop.Firmware.ReleaseFetcher do
  @moduledoc """
  Resolves the newest published build of a catalog image.

  This is the only part of the release lookup that touches the network, so it
  is a behaviour: tests swap in a stub through application config and never
  reach GitHub.
  """

  @type release :: %{version: binary(), uuid: binary() | nil, url: binary()}

  @callback resolve(repo :: binary(), asset :: binary()) ::
              {:ok, release()} | {:error, term()}

  @doc """
  The fetcher in use, overridable with the `:release_fetcher` key.
  """
  @spec impl() :: module()
  def impl do
    Application.get_env(:nerves_desktop, :release_fetcher, __MODULE__.GitHub)
  end
end
