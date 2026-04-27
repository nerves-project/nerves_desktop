defmodule NervesDesktop.FelLoader do
  @moduledoc """
  Handles downloading and caching USB FEL loaders.
  """
  require Logger

  @repo "gworkman/usb_fel_loaders"
  @boards ["trellis", "pine64"]

  def supported_boards, do: @boards

  @doc """
  Gets the latest release version.
  """
  def get_latest_version do
    case Req.get("https://api.github.com/repos/#{@repo}/releases/latest") do
      {:ok, %{status: 200, body: %{"tag_name" => tag}}} ->
        {:ok, tag}
      {:ok, %{status: status}} ->
        {:error, "Failed to get latest release: HTTP #{status}"}
      {:error, exception} ->
        {:error, "Network error: #{inspect(exception)}"}
    end
  end

  @doc """
  Downloads the loader for the specified board and version, caching it locally.
  """
  def download_loader(board, version) do
    if board not in @boards do
      {:error, "Unsupported board: #{board}"}
    else
      dl_dir = Path.join([System.user_home!(), ".nerves", "dl"])
      File.mkdir_p!(dl_dir)
      
      filename = "#{version}-#{board}.bin"
      cache_path = Path.join(dl_dir, filename)

      if File.exists?(cache_path) do
        Logger.info("Using cached FEL loader: #{cache_path}")
        {:ok, cache_path}
      else
        url = "https://github.com/#{@repo}/releases/download/#{version}/#{board}.bin"
        Logger.info("Downloading FEL loader from #{url}")
        
        # Use Req to download into the file
        case Req.get(url, into: File.stream!(cache_path)) do
          {:ok, %{status: 200}} ->
            Logger.info("Successfully downloaded FEL loader to #{cache_path}")
            {:ok, cache_path}
          {:ok, %{status: status}} ->
            File.rm(cache_path)
            {:error, "Download failed with HTTP #{status}"}
          {:error, exception} ->
            File.rm(cache_path)
            {:error, "Download error: #{inspect(exception)}"}
        end
      end
    end
  end
end
