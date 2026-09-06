defmodule NervesDesktop.CargoLock do
  @moduledoc """
  Reads and rewrites the version of a named package in a `Cargo.lock` file.

  Only the workspace's own package is expected to be rewritten; dependency
  entries are left alone.
  """

  @version_line ~r/^(\s*version\s*=\s*")([^"]*)(".*)$/
  @name_line ~r/^\s*name\s*=\s*"([^"]*)"/

  @doc "Returns the locked version of `name`."
  @spec version(binary(), binary()) :: {:ok, binary()} | :error
  def version(contents, name) do
    case rewrite(contents, name, & &1) do
      {:ok, _contents, version} -> {:ok, version}
      :error -> :error
    end
  end

  @doc "Replaces the locked version of `name` with `version`."
  @spec put_version(binary(), binary(), binary()) :: {:ok, binary()} | :error
  def put_version(contents, name, version) do
    case rewrite(contents, name, fn _current -> version end) do
      {:ok, contents, _previous} -> {:ok, contents}
      :error -> :error
    end
  end

  defp rewrite(contents, name, fun) do
    {lines, {_package, found}} =
      contents
      |> String.split("\n")
      |> Enum.map_reduce({nil, nil}, &rewrite_line(&1, &2, name, fun))

    if found, do: {:ok, Enum.join(lines, "\n"), found}, else: :error
  end

  defp rewrite_line(line, {package, found}, name, fun) do
    cond do
      declared_name = declared_name(line) ->
        {line, {declared_name, found}}

      package == name and is_nil(found) ->
        case Regex.run(@version_line, line) do
          [_, prefix, current, suffix] ->
            {prefix <> fun.(current) <> suffix, {package, current}}

          nil ->
            {line, {package, found}}
        end

      true ->
        {line, {package, found}}
    end
  end

  defp declared_name(line) do
    case Regex.run(@name_line, line) do
      [_, name] -> name
      nil -> nil
    end
  end
end
