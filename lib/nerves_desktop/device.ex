defmodule NervesDesktop.Device do
  @moduledoc """
  Normalizes devices discovered over the network and on serial ports.
  """

  @chip_mappings %{
    0x0403 => "FTDI USB-Serial",
    0x10C4 => "CP210x USB-Serial",
    0x1A86 => "CH34x USB-Serial"
  }

  @vids Map.keys(@chip_mappings)

  @advertised [
    :serial,
    :version,
    :product,
    :description,
    :platform,
    :architecture,
    :author,
    :uuid
  ]

  def format_address(addr) when is_tuple(addr) do
    case :inet.ntoa(addr) do
      {:error, _reason} -> ""
      formatted -> to_string(formatted)
    end
  end

  def format_address(_addr), do: ""

  def from_network(device) do
    addresses =
      (device[:addresses] || [])
      |> Enum.sort()
      |> Enum.map(&format_address/1)
      |> Enum.reject(&(&1 == ""))

    display_ip =
      case addresses do
        [] -> device[:ip] || ""
        [first | _rest] -> first
      end

    target =
      if device[:hostname] && device[:hostname] != "" do
        device.hostname
      else
        List.first(addresses) || device[:ip] || ""
      end

    Map.merge(device, %{
      id: "network:#{target}",
      name: device[:name] || device[:hostname] || target,
      target: target,
      ip: display_ip,
      type: :network,
      nerves?: nerves?(device),
      product: device[:product],
      version: device[:version],
      platform: device[:platform]
    })
  end

  # Only Nerves firmware advertises these fields, and its default hostname is nerves-xxxx.
  defp nerves?(device) do
    Enum.any?(@advertised, &device[&1]) or nerves_name?(device[:hostname]) or
      nerves_name?(device[:name])
  end

  defp nerves_name?(name) when is_binary(name),
    do: name |> String.downcase() |> String.starts_with?("nerves")

  defp nerves_name?(_name), do: false

  def from_uart(enumerate_output) do
    enumerate_output
    |> Enum.filter(fn {_port, info} -> info[:vendor_id] in @vids end)
    |> Enum.map(fn {port, info} ->
      vendor_id = info[:vendor_id]
      manufacturer = info[:manufacturer] || ""
      chip_name = @chip_mappings[vendor_id] || "USB-Serial Device"
      display_name = if manufacturer == "", do: chip_name, else: manufacturer

      %{
        id: "uart:#{port}",
        name: display_name,
        hostname: port,
        target: port,
        type: :uart,
        nerves?: false,
        ip: nil,
        product: info[:description] || chip_name,
        version: nil,
        platform: nil,
        manufacturer: info[:manufacturer],
        vendor_id: info[:vendor_id],
        product_id: info[:product_id]
      }
    end)
  end
end
