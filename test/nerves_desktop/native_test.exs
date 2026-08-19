defmodule NervesDesktop.NativeTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Native

  # The test suite runs without the Tauri shell, which is the case that used to
  # raise `unknown registry: ElixirKit.PubSub.Registry` and take the LiveView
  # down on mount.
  test "reports the shell as unavailable when it is not running" do
    refute Native.available?()
  end

  test "subscribing without a shell is a no-op rather than a crash" do
    assert Native.subscribe("file_dialog_result") == :ok
  end

  test "broadcasting without a shell is a no-op rather than a crash" do
    assert Native.broadcast("messages", "open_file_dialog") == :ok
  end
end
