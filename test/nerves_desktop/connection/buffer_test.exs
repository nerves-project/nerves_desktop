defmodule NervesDesktop.Connection.BufferTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Connection.Buffer

  test "accumulates chunks in order" do
    buffer = Buffer.new() |> Buffer.push("one ") |> Buffer.push("two")
    assert Buffer.to_binary(buffer) == "one two"
  end

  test "drops the oldest chunks instead of the whole buffer" do
    buffer =
      Buffer.new(10)
      |> Buffer.push("aaaa")
      |> Buffer.push("bbbb")
      |> Buffer.push("cccc")

    assert Buffer.to_binary(buffer) == "bbbbcccc"
  end

  test "keeps the tail of a chunk larger than the limit" do
    buffer = Buffer.new(4) |> Buffer.push("abcdefgh")
    assert Buffer.to_binary(buffer) == "efgh"
  end

  test "an empty buffer serializes to an empty binary" do
    assert Buffer.to_binary(Buffer.new()) == ""
  end
end
