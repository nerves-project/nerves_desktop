defmodule NervesDesktop.Connection.Buffer do
  @moduledoc """
  Bounded scrollback buffer for connection output. Chunks are held newest-first
  as iodata and trimmed from the oldest end once the byte limit is exceeded.
  """

  @default_limit 50_000

  defstruct chunks: [], size: 0, limit: @default_limit

  @type t :: %__MODULE__{chunks: [binary()], size: non_neg_integer(), limit: pos_integer()}

  @spec new(pos_integer()) :: t()
  def new(limit \\ @default_limit), do: %__MODULE__{limit: limit}

  @spec push(t(), binary()) :: t()
  def push(%__MODULE__{limit: limit} = buffer, data) when is_binary(data) do
    if byte_size(data) >= limit do
      %{buffer | chunks: [binary_part(data, byte_size(data) - limit, limit)], size: limit}
    else
      trim(%{buffer | chunks: [data | buffer.chunks], size: buffer.size + byte_size(data)})
    end
  end

  @spec to_binary(t()) :: binary()
  def to_binary(%__MODULE__{chunks: chunks}) do
    chunks |> Enum.reverse() |> IO.iodata_to_binary()
  end

  defp trim(%{size: size, limit: limit} = buffer) when size <= limit, do: buffer

  defp trim(buffer) do
    {kept, size} = drop_oldest(Enum.reverse(buffer.chunks), buffer.size, buffer.limit)
    %{buffer | chunks: Enum.reverse(kept), size: size}
  end

  defp drop_oldest([chunk | rest], size, limit) when size > limit do
    drop_oldest(rest, size - byte_size(chunk), limit)
  end

  defp drop_oldest(chunks, size, _limit), do: {chunks, size}
end
