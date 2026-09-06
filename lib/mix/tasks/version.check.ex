defmodule Mix.Tasks.Version.Check do
  @shortdoc "Verifies every version in the project matches the VERSION file"

  @moduledoc """
  Verifies that the project versions agree with the `VERSION` file.

  `VERSION` is the single source of truth. `mix.exs` reads it directly, and
  Tauri inherits its version from `src-tauri/Cargo.toml`, which this task
  checks. Run `mix version.sync` to fix a mismatch.

      $ mix version.check
      $ mix version.check --tag v0.2.0

  Passing `--tag` additionally asserts that a git tag names the same version,
  which is how the release workflow fails before building five platforms.
  """

  use Mix.Task

  alias NervesDesktop.CargoLock
  alias NervesDesktop.CargoManifest
  alias NervesDesktop.ProjectVersion

  @impl Mix.Task
  def run(args) do
    {opts, _rest} = OptionParser.parse!(args, strict: [tag: :string])

    version = ProjectVersion.read!()

    check_cargo!(version)
    check_cargo_lock!(version)
    check_tauri_conf!()
    if tag = opts[:tag], do: check_tag!(version, tag)

    Mix.shell().info("Version #{version} is consistent across the project.")
  end

  defp check_cargo!(version) do
    path = ProjectVersion.cargo_manifest_path()

    case CargoManifest.version(File.read!(path)) do
      {:ok, ^version} ->
        :ok

      {:ok, other} ->
        Mix.raise("""
        #{path} declares version #{other}, but VERSION says #{version}.

        Run `mix version.sync` to update it.
        """)

      :error ->
        Mix.raise("#{path} has no [package] version to check.")
    end
  end

  defp check_cargo_lock!(version) do
    path = ProjectVersion.cargo_lock_path()
    name = ProjectVersion.cargo_package_name()

    case CargoLock.version(File.read!(path), name) do
      {:ok, ^version} ->
        :ok

      {:ok, other} ->
        Mix.raise("""
        #{path} locks #{name} at version #{other}, but VERSION says #{version}.

        Run `mix version.sync` to update it.
        """)

      :error ->
        Mix.raise("#{path} has no locked version for #{name}.")
    end
  end

  defp check_tauri_conf!() do
    path = ProjectVersion.tauri_config_path()

    case path |> File.read!() |> Jason.decode!() do
      %{"version" => version} ->
        Mix.raise("""
        #{path} pins version #{version}.

        Remove the "version" key so Tauri inherits it from Cargo.toml, which is
        kept in sync with VERSION.
        """)

      _config ->
        :ok
    end
  end

  defp check_tag!(version, tag) do
    tagged = String.trim_leading(tag, "v")

    if tagged != version do
      Mix.raise("""
      Tag #{tag} does not match VERSION (#{version}).

      Update VERSION, run `mix version.sync`, and commit before tagging.
      """)
    end
  end
end
