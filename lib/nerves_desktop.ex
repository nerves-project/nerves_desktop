defmodule NervesDesktop do
  @moduledoc """
  NervesDesktop keeps the contexts that define your domain
  and business logic.

  Contexts are also responsible for managing your data, regardless
  if it comes from the database, an external API or others.
  """

  @doc """
  The version to show in the UI.

  Builds that were not cut from a tag are suffixed with `-dev`.
  """
  @spec version() :: binary()
  def version do
    version(Application.spec(:nerves_desktop, :vsn), release_build?())
  end

  defp release_build?, do: Application.get_env(:nerves_desktop, :release_build?, false)

  @doc false
  @spec version(charlist() | binary(), boolean()) :: binary()
  def version(vsn, release_build?) do
    vsn = to_string(vsn)
    if release_build?, do: vsn, else: vsn <> "-dev"
  end
end
