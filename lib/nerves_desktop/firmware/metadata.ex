defmodule NervesDesktop.Firmware.Metadata do
  @moduledoc """
  Reads the metadata block that `fwup -m` prints for a firmware archive.

  `fwup` writes `meta.conf` at the front of the archive, so this works on a
  partial download as well as a whole file. Roughly 16 KB is enough to cover
  the images in the catalog.
  """

  @type t :: %{
          product: binary() | nil,
          version: binary() | nil,
          platform: binary() | nil,
          uuid: binary() | nil
        }

  @fields %{
    "meta-product" => :product,
    "meta-version" => :version,
    "meta-platform" => :platform,
    "meta-uuid" => :uuid
  }

  @doc """
  Parses `fwup -m` output.

  Returns `{:error, :no_metadata}` when the output holds none, which is what a
  truncated or non-firmware file produces.
  """
  @spec parse(binary()) :: {:ok, t()} | {:error, :no_metadata}
  def parse(output) when is_binary(output) do
    found =
      output
      |> String.split("\n", trim: true)
      |> Enum.reduce(%{}, &collect/2)

    if map_size(found) == 0 do
      {:error, :no_metadata}
    else
      {:ok, Map.merge(%{product: nil, version: nil, platform: nil, uuid: nil}, found)}
    end
  end

  defp collect(line, acc) do
    # fwup quotes values that may contain spaces and leaves the rest bare.
    case String.split(String.trim(line), "=", parts: 2) do
      [key, value] ->
        case Map.fetch(@fields, key) do
          {:ok, field} -> Map.put(acc, field, unquote_value(value))
          :error -> acc
        end

      _ ->
        acc
    end
  end

  defp unquote_value(value) do
    value
    |> String.trim()
    |> String.trim(~s("))
  end
end
