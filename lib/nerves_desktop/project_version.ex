defmodule NervesDesktop.ProjectVersion do
  @moduledoc """
  Locates the `VERSION` file and the project files kept in sync with it.
  """

  @doc "The version declared in the VERSION file."
  @spec read!() :: binary()
  def read! do
    path() |> File.read!() |> String.trim()
  end

  @spec path() :: binary()
  def path, do: Path.join(root(), "VERSION")

  @spec cargo_manifest_path() :: binary()
  def cargo_manifest_path, do: Path.join([root(), "src-tauri", "Cargo.toml"])

  @spec cargo_lock_path() :: binary()
  def cargo_lock_path, do: Path.join([root(), "src-tauri", "Cargo.lock"])

  @spec cargo_package_name() :: binary()
  def cargo_package_name, do: "nerves_desktop"

  @spec tauri_config_path() :: binary()
  def tauri_config_path, do: Path.join([root(), "src-tauri", "tauri.conf.json"])

  defp root, do: File.cwd!()
end
