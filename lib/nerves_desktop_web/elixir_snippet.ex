defmodule NervesDesktopWeb.ElixirSnippet do
  @moduledoc """
  Highlights the static Elixir samples this app renders on screen.

  This is deliberately not a general lexer. It recognises the constructs the
  bundled snippets use and emits anything else as plain text, so unfamiliar
  input degrades to an unhighlighted sample rather than to wrong colours.
  """

  @keywords ~w(after and case catch cond do else end false fn for if in nil
               not or receive rescue true try unless when with)

  @doc """
  Renders `code` as safe HTML, wrapping recognised tokens in `tok-*` spans.
  """
  def to_html(code) when is_binary(code) do
    {:safe, code |> scan() |> Enum.map(&render/1)}
  end

  defp render({:text, text}), do: escape(text)

  defp render({class, text}) do
    [~s(<span class="tok-), Atom.to_string(class), ~s(">), escape(text), "</span>"]
  end

  defp escape(text), do: text |> Phoenix.HTML.html_escape() |> Phoenix.HTML.safe_to_string()

  defp scan(code), do: code |> scan([]) |> Enum.reverse()

  defp scan(<<>>, acc), do: acc

  defp scan(<<?", rest::binary>>, acc) do
    {tokens, rest} = string(rest, ~s("), [])
    scan(rest, tokens ++ acc)
  end

  # A `#` only opens a comment out here; inside a string it starts interpolation.
  defp scan(<<?#, rest::binary>>, acc) do
    {body, rest} = take_line(rest, "")
    scan(rest, [{:comment, "#" <> body} | acc])
  end

  defp scan(<<?:, c::utf8, rest::binary>>, acc) when c in ?a..?z or c == ?_ do
    {name, rest} = take_ident(rest, <<c::utf8>>)
    scan(rest, [{:atom, ":" <> name} | acc])
  end

  defp scan(<<c::utf8, _::binary>> = code, acc) when c in ?A..?Z do
    {name, rest} = take_ident(code, "")
    scan(rest, [{:mod, name} | acc])
  end

  defp scan(<<c::utf8, _::binary>> = code, acc) when c in ?a..?z or c == ?_ do
    {name, rest} = take_ident(code, "")
    {token, rest} = classify_ident(name, rest)
    scan(rest, [token | acc])
  end

  defp scan(<<c::utf8, _::binary>> = code, acc) when c in ?0..?9 do
    {number, rest} = take_number(code, "")
    scan(rest, [{:num, number} | acc])
  end

  defp scan(<<c::utf8, rest::binary>>, acc), do: scan(rest, [{:text, <<c::utf8>>} | acc])

  # `key:` is only a keyword key when a value follows, which rules out `::`.
  defp classify_ident(name, <<?:, next::utf8, _::binary>> = rest) when next != ?: do
    <<?:, rest::binary>> = rest
    {{:key, name <> ":"}, rest}
  end

  defp classify_ident(name, <<?(, _::binary>> = rest), do: {{:fun, name}, rest}

  defp classify_ident(name, rest) when name in @keywords, do: {{:kw, name}, rest}
  defp classify_ident(name, rest), do: {{:text, name}, rest}

  # Returns tokens in reverse order, matching the accumulator `scan/2` builds.
  defp string(<<>>, buf, acc), do: {flush(buf, acc), ""}

  defp string(<<?\\, c::utf8, rest::binary>>, buf, acc),
    do: string(rest, buf <> <<?\\, c::utf8>>, acc)

  defp string(<<?", rest::binary>>, buf, acc), do: {flush(buf <> ~s("), acc), rest}

  defp string(<<?#, ?{, rest::binary>>, buf, acc) do
    {source, rest} = interpolation(rest, "", 0)
    acc = [{:interp, "\#{"} | flush(buf, acc)]
    acc = [{:interp, "}"} | Enum.reduce(scan(source), acc, &[&1 | &2])]
    string(rest, "", acc)
  end

  defp string(<<c::utf8, rest::binary>>, buf, acc), do: string(rest, buf <> <<c::utf8>>, acc)

  defp flush("", acc), do: acc
  defp flush(buf, acc), do: [{:str, buf} | acc]

  defp interpolation(<<>>, buf, _depth), do: {buf, ""}
  defp interpolation(<<?}, rest::binary>>, buf, 0), do: {buf, rest}

  defp interpolation(<<?}, rest::binary>>, buf, depth),
    do: interpolation(rest, buf <> "}", depth - 1)

  defp interpolation(<<?{, rest::binary>>, buf, depth),
    do: interpolation(rest, buf <> "{", depth + 1)

  # A nested string may hold braces of its own, so step over it whole.
  defp interpolation(<<?", rest::binary>>, buf, depth) do
    {literal, rest} = raw_string(rest, ~s("))
    interpolation(rest, buf <> literal, depth)
  end

  defp interpolation(<<c::utf8, rest::binary>>, buf, depth),
    do: interpolation(rest, buf <> <<c::utf8>>, depth)

  defp raw_string(<<>>, buf), do: {buf, ""}

  defp raw_string(<<?\\, c::utf8, rest::binary>>, buf),
    do: raw_string(rest, buf <> <<?\\, c::utf8>>)

  defp raw_string(<<?", rest::binary>>, buf), do: {buf <> ~s("), rest}
  defp raw_string(<<c::utf8, rest::binary>>, buf), do: raw_string(rest, buf <> <<c::utf8>>)

  defp take_ident(<<c::utf8, rest::binary>>, acc)
       when c in ?a..?z or c in ?A..?Z or c in ?0..?9 or c == ?_,
       do: take_ident(rest, acc <> <<c::utf8>>)

  defp take_ident(<<c::utf8, rest::binary>>, acc) when c in ~c"?!",
    do: {acc <> <<c::utf8>>, rest}

  defp take_ident(rest, acc), do: {acc, rest}

  defp take_number(<<c::utf8, rest::binary>>, acc) when c in ?0..?9 or c == ?_,
    do: take_number(rest, acc <> <<c::utf8>>)

  defp take_number(rest, acc), do: {acc, rest}

  defp take_line(<<?\n, _::binary>> = rest, acc), do: {acc, rest}
  defp take_line(<<>>, acc), do: {acc, ""}
  defp take_line(<<c::utf8, rest::binary>>, acc), do: take_line(rest, acc <> <<c::utf8>>)
end
