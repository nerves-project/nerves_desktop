defmodule Mix.Tasks.Version.Sync do
  @shortdoc "Writes the VERSION file's version into src-tauri/Cargo.toml"

  @moduledoc """
  Propagates the `VERSION` file into the files that cannot read it themselves.

  `mix.exs` reads `VERSION` directly and Tauri inherits from
  `src-tauri/Cargo.toml`, so Cargo is the only file this needs to rewrite.

      $ mix version.sync
  """

  use Mix.Task

  alias NervesDesktop.CargoLock
  alias NervesDesktop.CargoManifest
  alias NervesDesktop.ProjectVersion

  @impl Mix.Task
  def run(_args) do
    version = ProjectVersion.read!()

    updated? =
      [
        sync!(
          ProjectVersion.cargo_manifest_path(),
          version,
          &CargoManifest.put_version(&1, version)
        ),
        sync!(ProjectVersion.cargo_lock_path(), version, fn contents ->
          CargoLock.put_version(contents, ProjectVersion.cargo_package_name(), version)
        end)
      ]
      |> Enum.any?()

    if updated? do
      # Mix only regenerates the .app file when mix.exs changes, not VERSION
      File.touch!("mix.exs")
    end
  end

  defp sync!(path, version, fun) do
    contents = File.read!(path)

    case fun.(contents) do
      {:ok, ^contents} ->
        Mix.shell().info("#{path} is already at #{version}.")
        false

      {:ok, updated} ->
        File.write!(path, updated)
        Mix.shell().info("Updated #{path} to #{version}.")
        true

      :error ->
        Mix.raise("#{path} has no version to update.")
    end
  end
end
