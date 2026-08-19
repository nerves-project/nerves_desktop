defmodule NervesDesktopWeb.ElixirSnippetTest do
  use ExUnit.Case, async: true

  alias NervesDesktopWeb.ElixirSnippet

  defp html(code), do: code |> ElixirSnippet.to_html() |> Phoenix.HTML.safe_to_string()

  defp text(code) do
    code
    |> html()
    |> String.replace(~r/<[^>]*>/, "")
    |> String.replace("&quot;", ~s("))
    |> String.replace("&#39;", "'")
    |> String.replace("&lt;", "<")
    |> String.replace("&gt;", ">")
    |> String.replace("&amp;", "&")
  end

  test "tags modules, calls, atoms, keyword keys, strings, and numbers" do
    out = html(~s|MdnsLite.add(%{id: :nerves_device, port: 0, name: "pi"})|)

    assert out =~ ~s(<span class="tok-mod">MdnsLite</span>)
    assert out =~ ~s(<span class="tok-fun">add</span>)
    assert out =~ ~s(<span class="tok-key">id:</span>)
    assert out =~ ~s(<span class="tok-atom">:nerves_device</span>)
    assert out =~ ~s(<span class="tok-num">0</span>)
    assert out =~ ~s(<span class="tok-str">&quot;pi&quot;</span>)
  end

  test "highlights inside string interpolation, including nested strings" do
    out = html(~s|"product=\#{Nerves.Runtime.KV.get_active("nerves_fw_product")}"|)

    assert out =~ ~s(<span class="tok-interp">\#{</span>)
    assert out =~ ~s(<span class="tok-mod">Nerves</span>)
    assert out =~ ~s(<span class="tok-mod">KV</span>)
    assert out =~ ~s(<span class="tok-fun">get_active</span>)
    assert out =~ ~s(<span class="tok-str">&quot;nerves_fw_product&quot;</span>)
    assert out =~ ~s(<span class="tok-interp">}</span>)
  end

  test "does not mistake a module attribute or :: for a keyword key" do
    assert html("value :: integer") =~ "::"
    refute html("value :: integer") =~ ~s(class="tok-key")
  end

  test "escapes markup rather than emitting it" do
    out = html(~s|"<script>alert(1)</script>"|)

    refute out =~ "<script>"
    assert out =~ "&lt;script&gt;"
  end

  test "round-trips the source exactly" do
    for code <- [
          ~s|MdnsLite.add(%{id: :x, port: 0})|,
          ~s|"a=\#{B.c("d")} & e"|,
          "# a comment\nvalue = 1\n",
          ~s|"unterminated|,
          "fn x -> x end"
        ] do
      assert text(code) == code
    end
  end
end
