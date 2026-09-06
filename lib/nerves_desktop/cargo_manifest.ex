defmodule NervesDesktop.CargoManifest do
  @moduledoc """
  Reads and rewrites the `version` key of a Cargo manifest's `[package]`
  section, leaving dependency versions alone.
  """

  @version_line ~r/^(\s*version\s*=\s*")([^"]*)(".*)$/
  @section_header ~r/^\s*\[/

  @doc "Returns the `[package]` version declared in `contents`."
  @spec version(binary()) :: {:ok, binary()} | :error
  def version(contents) do
    case rewrite(contents, & &1) do
      {:ok, _contents, version} -> {:ok, version}
      :error -> :error
    end
  end

  @doc "Replaces the `[package]` version in `contents` with `version`."
  @spec put_version(binary(), binary()) :: {:ok, binary()} | :error
  def put_version(contents, version) do
    case rewrite(contents, fn _current -> version end) do
      {:ok, contents, _previous} -> {:ok, contents}
      :error -> :error
    end
  end

  defp rewrite(contents, fun) do
    {lines, {_in_package?, found}} =
      contents
      |> String.split("\n")
      |> Enum.map_reduce({false, nil}, &rewrite_line(&1, &2, fun))

    if found, do: {:ok, Enum.join(lines, "\n"), found}, else: :error
  end

  defp rewrite_line(line, {in_package?, found}, fun) do
    cond do
      Regex.match?(@section_header, line) ->
        {line, {String.trim(line) == "[package]", found}}

      in_package? and is_nil(found) ->
        case Regex.run(@version_line, line) do
          [_, prefix, current, suffix] ->
            {prefix <> fun.(current) <> suffix, {in_package?, current}}

          nil ->
            {line, {in_package?, found}}
        end

      true ->
        {line, {in_package?, found}}
    end
  end
end
