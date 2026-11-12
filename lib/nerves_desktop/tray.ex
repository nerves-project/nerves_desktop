defmodule NervesDesktop.Tray do
  @moduledoc """
  Describes the tray menu's device list for the Tauri shell to render.

  The menu is native, so the shell builds it. Everything it needs to know about
  a device is decided here: which list it belongs in, what it is called, where
  its console lives, and what can be copied from it.
  """

  alias NervesDesktop.Native

  @topic "tray"

  @doc """
  Sends the device list to the tray menu.
  """
  @spec update([map()]) :: :ok
  def update(devices), do: Native.broadcast(@topic, payload(devices))

  @doc """
  Encodes devices as the JSON the shell turns into menu items.
  """
  @spec payload([map()]) :: binary()
  def payload(devices) do
    {nerves, other} =
      devices
      |> Enum.sort_by(&String.downcase(label(&1)))
      |> Enum.split_with(&(&1[:nerves?] == true))

    Jason.encode!(%{nerves: Enum.map(nerves, &entry/1), other: Enum.map(other, &entry/1)})
  end

  defp entry(device) do
    %{label: label(device), console: console_path(device), copy: copy_items(device)}
  end

  defp label(%{type: :uart} = device), do: "#{device.name} (#{device.target})"
  defp label(device), do: device.name

  defp copy_items(%{type: :uart} = device), do: copy_item("Copy port", device.target)

  defp copy_items(device) do
    copy_item("Copy hostname", device[:hostname]) ++
      copy_item("Copy IP (#{device[:ip]})", device[:ip])
  end

  defp copy_item(label, value) when is_binary(value) and value != "",
    do: [%{label: label, value: value}]

  defp copy_item(_label, _value), do: []

  defp console_path(device) do
    "/console?" <> URI.encode_query(target: device.target, name: device.name, connect: true)
  end
end
