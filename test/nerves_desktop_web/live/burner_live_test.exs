defmodule NervesDesktopWeb.BurnerLiveTest do
  use ExUnit.Case, async: true

  alias NervesDesktopWeb.BurnerLive

  # The template drives both the button's disabled state and its label from
  # this predicate, so pinning it here pins the rule that the write button
  # cannot be pressed while fwup is running.
  describe "writing?/1" do
    test "covers every status that means a write is in flight" do
      assert BurnerLive.writing?(:downloading)
      assert BurnerLive.writing?(:burning)
    end

    test "is false once the write has stopped" do
      refute BurnerLive.writing?(:idle)
      refute BurnerLive.writing?(:success)
      refute BurnerLive.writing?(:error)
    end
  end
end
