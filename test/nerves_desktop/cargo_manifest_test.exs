defmodule NervesDesktop.CargoManifestTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.CargoManifest

  @manifest """
  [package]
  name = "nerves-desktop"
  version = "0.1.0"
  edition = "2021"

  [build-dependencies]
  tauri-build = { version = "2", features = [] }

  [dependencies]
  tauri = { version = "2", features = [] }
  """

  describe "version/1" do
    test "reads the version from the package section" do
      assert CargoManifest.version(@manifest) == {:ok, "0.1.0"}
    end

    test "ignores versions outside the package section" do
      manifest = """
      [dependencies]
      tauri = "2"
      version = "9.9.9"
      """

      assert CargoManifest.version(manifest) == :error
    end

    test "returns an error when the package has no version" do
      assert CargoManifest.version("[package]\nname = \"nerves-desktop\"\n") == :error
    end
  end

  describe "put_version/2" do
    test "rewrites the package version" do
      assert {:ok, updated} = CargoManifest.put_version(@manifest, "0.2.0")
      assert CargoManifest.version(updated) == {:ok, "0.2.0"}
    end

    test "leaves dependency versions untouched" do
      assert {:ok, updated} = CargoManifest.put_version(@manifest, "0.2.0")
      assert updated =~ ~s(tauri = { version = "2", features = [] })
      assert updated =~ ~s(tauri-build = { version = "2", features = [] })
    end

    test "preserves the rest of the manifest" do
      assert {:ok, updated} = CargoManifest.put_version(@manifest, "0.2.0")
      assert updated =~ ~s(name = "nerves-desktop")
      assert updated =~ ~s(edition = "2021")
    end

    test "returns an error when there is no package version to rewrite" do
      assert CargoManifest.put_version("[dependencies]\ntauri = \"2\"\n", "0.2.0") == :error
    end
  end
end
