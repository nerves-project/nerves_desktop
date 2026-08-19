defmodule NervesDesktop.HostInfoTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.HostInfo

  test "derives a utf-8 locale from the tauri locale" do
    env = HostInfo.locale_env(%{"locale" => "en-GB"})
    assert {~c"LANG", ~c"en_GB.UTF-8"} in env
    assert {~c"TERM", ~c"xterm-256color"} in env
  end

  test "falls back when the locale is missing or blank" do
    for info <- [%{}, %{"locale" => ""}, %{"locale" => nil}] do
      assert {~c"LANG", ~c"en_US.UTF-8"} in HostInfo.locale_env(info)
    end
  end
end
