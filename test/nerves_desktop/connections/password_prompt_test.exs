defmodule NervesDesktop.Connections.PasswordPromptTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Connections.PasswordPrompt

  test "detects a prompt in a single chunk" do
    assert {:send, _state} = PasswordPrompt.feed(PasswordPrompt.new(), "root@host's password: ")
  end

  test "detects a prompt split across chunks" do
    {:wait, state} = PasswordPrompt.feed(PasswordPrompt.new(), "root@host's Pass")
    assert {:send, _state} = PasswordPrompt.feed(state, "word: ")
  end

  test "ignores the word password in mid-stream output" do
    assert {:wait, _state} =
             PasswordPrompt.feed(PasswordPrompt.new(), "Warning: password: expired, see docs\r\n")
  end

  test "answers a retry prompt after a wrong password" do
    {:send, state} = PasswordPrompt.feed(PasswordPrompt.new(), "password: ")
    {:wait, state} = PasswordPrompt.feed(state, "\r\nPermission denied\r\n")
    assert {:send, _state} = PasswordPrompt.feed(state, "password: ")
  end

  test "gives up after three attempts" do
    state =
      Enum.reduce(1..3, PasswordPrompt.new(), fn _i, acc ->
        {:send, acc} = PasswordPrompt.feed(acc, "password: ")
        acc
      end)

    assert {:wait, _state} = PasswordPrompt.feed(state, "password: ")
  end
end
