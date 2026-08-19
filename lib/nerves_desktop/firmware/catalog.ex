defmodule NervesDesktop.Firmware.Catalog do
  @moduledoc """
  Matches a discovered device against the firmware images this app knows how to
  download.

  A Nerves image advertises `nerves_fw_product`, which is the name of the
  project it was built from, and that is the basename of the catalog entry's
  GitHub repo. That holds for every image in the catalog, so the repo is the
  join key.
  """

  alias NervesBurner.FirmwareImages

  @type config :: map()

  @doc """
  Finds the catalog image a device is running.

  Only network devices can be matched: an over-the-air update needs an SSH
  channel, and a target shipped only as a disk image has no `.fw` to send.
  """
  @spec match(map()) :: {:ok, binary(), config()} | :no_match
  def match(%{type: :network, product: product, platform: platform})
      when is_binary(product) and is_binary(platform) do
    Enum.find_value(FirmwareImages.list(), :no_match, fn {name, config} ->
      if Path.basename(config.repo) == product and updatable_target?(config, platform) do
        {:ok, name, config}
      end
    end)
  end

  def match(_device), do: :no_match

  @doc """
  Whether this device could be updated from the catalog at all.
  """
  @spec updatable?(map()) :: boolean()
  def updatable?(device), do: match(device) != :no_match

  # The published builds ship a documented password and authorize no developer
  # key, so it is a property of the image rather than something to ask for.
  # nerves_ssh accepts any username alongside it, so these all log in as root.
  @default_passwords %{
    "circuits_quickstart" => "circuits",
    "nerves_livebook" => "nerves",
    "kiosk_demo" => "kiosk"
  }

  @doc """
  The documented password for a published image, when it has one.
  """
  @spec default_password(config()) :: binary() | nil
  def default_password(config), do: Map.get(@default_passwords, Path.basename(config.repo))

  @doc """
  The documented password for whatever image a device reports running.

  Unlike `match/1` this ignores the board and the transport, because the
  password belongs to the image rather than to any particular build of it.
  """
  @spec password_for(map() | nil) :: binary() | nil
  def password_for(%{product: product}) when is_binary(product),
    do: Map.get(@default_passwords, product)

  def password_for(_device), do: nil

  @doc """
  The name of the `.fw` release asset for a target.
  """
  @spec asset_name(config(), binary()) :: binary()
  def asset_name(config, target), do: config.fw_asset_pattern.(target)

  defp updatable_target?(config, target) do
    target in config.targets and not image_only?(config, target)
  end

  # Some targets ship a disk image rather than a firmware archive, so there is
  # nothing to stream to a running device.
  defp image_only?(config, target) do
    case get_in(config, [:overrides, target]) do
      %{use_image_asset: true} -> true
      _ -> false
    end
  end
end
