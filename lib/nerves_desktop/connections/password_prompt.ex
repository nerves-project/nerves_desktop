defmodule NervesDesktop.Connections.PasswordPrompt do
  @moduledoc """
  Detects SSH password prompts in a byte stream that may split them across reads.
  """

  @window 256
  @max_attempts 3

  # Anchored to the end of the window: a prompt is the last thing written before
  # ssh blocks on input, whereas a banner mentioning it is followed by more bytes
  @prompt ~r/[Pp]assword:\s*\z/

  defstruct window: "", attempts: 0

  @type t :: %__MODULE__{window: binary(), attempts: non_neg_integer()}

  @spec new() :: t()
  def new, do: %__MODULE__{}

  @spec feed(t(), binary()) :: {:send | :wait, t()}
  def feed(%__MODULE__{} = state, data) when is_binary(data) do
    window = trim_window(state.window <> data)

    if state.attempts < @max_attempts and Regex.match?(@prompt, window) do
      {:send, %{state | attempts: state.attempts + 1, window: ""}}
    else
      {:wait, %{state | window: window}}
    end
  end

  defp trim_window(bin) when byte_size(bin) <= @window, do: bin
  defp trim_window(bin), do: binary_part(bin, byte_size(bin) - @window, @window)
end
