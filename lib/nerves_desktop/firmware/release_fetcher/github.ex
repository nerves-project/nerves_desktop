defmodule NervesDesktop.Firmware.ReleaseFetcher.GitHub do
  @moduledoc """
  Resolves releases from the GitHub API.

  The UUID lives in the archive's metadata block, which `fwup` writes at the
  front of the file, so a range request for the first few kilobytes is enough
  to read it without pulling down tens of megabytes.
  """

  @behaviour NervesDesktop.Firmware.ReleaseFetcher

  alias NervesDesktop.Firmware.Metadata

  require Logger

  # 4 KB is not enough for the catalog images and 6 KB is; this leaves room.
  @head_bytes 16_384

  @impl true
  def resolve(repo, asset) do
    with {:ok, tag, url} <- latest_asset(repo, asset) do
      {:ok, %{version: normalize_version(tag), uuid: uuid(url), url: url}}
    end
  end

  defp latest_asset(repo, asset) do
    case Req.get("https://api.github.com/repos/#{repo}/releases/latest",
           headers: [accept: "application/vnd.github+json"],
           receive_timeout: 10_000
         ) do
      {:ok, %{status: 200, body: %{"tag_name" => tag, "assets" => assets}}} ->
        case Enum.find(assets, &(&1["name"] == asset)) do
          %{"browser_download_url" => url} -> {:ok, tag, url}
          nil -> {:error, :asset_not_found}
        end

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Without fwup we cannot read the UUID, so the caller falls back to comparing
  # version strings rather than losing the check entirely.
  defp uuid(url) do
    with path when is_binary(path) <- System.find_executable("fwup"),
         {:ok, head} <- firmware_head(url),
         {:ok, file} <- write_temp(head),
         {output, _} <- System.cmd(path, ["-m", "-i", file], stderr_to_stdout: true),
         _ <- File.rm(file),
         {:ok, meta} <- Metadata.parse(output) do
      meta.uuid
    else
      other ->
        Logger.debug("[ReleaseIndex] could not read firmware uuid: #{inspect(other)}")
        nil
    end
  end

  defp firmware_head(url) do
    case Req.get(url, headers: [range: "bytes=0-#{@head_bytes - 1}"], receive_timeout: 20_000) do
      {:ok, %{status: status, body: body}} when status in [200, 206] and is_binary(body) ->
        {:ok, body}

      {:ok, %{status: status}} ->
        {:error, {:http, status}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp write_temp(bytes) do
    file = Path.join(System.tmp_dir!(), "nd-fwhead-#{System.unique_integer([:positive])}.fw")

    case File.write(file, bytes) do
      :ok -> {:ok, file}
      error -> error
    end
  end

  # Release tags carry a leading v; firmware metadata does not.
  defp normalize_version("v" <> version), do: version
  defp normalize_version(version), do: version
end
