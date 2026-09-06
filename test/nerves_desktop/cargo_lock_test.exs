defmodule NervesDesktop.CargoLockTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.CargoLock

  @lock """
  version = 4

  [[package]]
  name = "anyhow"
  version = "1.0.100"

  [[package]]
  name = "nerves_desktop"
  version = "0.1.0"
  dependencies = [
   "serde",
   "tauri",
  ]

  [[package]]
  name = "tauri"
  version = "2.9.1"
  """

  describe "version/2" do
    test "reads the version of the named package" do
      assert CargoLock.version(@lock, "nerves_desktop") == {:ok, "0.1.0"}
    end

    test "reads the version of a dependency" do
      assert CargoLock.version(@lock, "tauri") == {:ok, "2.9.1"}
    end

    test "returns an error for an unlocked package" do
      assert CargoLock.version(@lock, "nope") == :error
    end
  end

  describe "put_version/3" do
    test "rewrites only the named package" do
      assert {:ok, updated} = CargoLock.put_version(@lock, "nerves_desktop", "0.2.0")
      assert CargoLock.version(updated, "nerves_desktop") == {:ok, "0.2.0"}
      assert CargoLock.version(updated, "anyhow") == {:ok, "1.0.100"}
      assert CargoLock.version(updated, "tauri") == {:ok, "2.9.1"}
    end

    test "preserves the rest of the entry" do
      assert {:ok, updated} = CargoLock.put_version(@lock, "nerves_desktop", "0.2.0")
      assert updated =~ ~s(dependencies = [)
      assert updated =~ ~s("serde",)
      assert String.starts_with?(updated, "version = 4")
    end

    test "returns an error for an unlocked package" do
      assert CargoLock.put_version(@lock, "nope", "0.2.0") == :error
    end
  end
end
