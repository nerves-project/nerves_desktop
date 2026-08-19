defmodule NervesDesktop.Firmware.CatalogTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Firmware.Catalog

  defp device(attrs \\ %{}) do
    Map.merge(
      %{type: :network, product: "circuits_quickstart", platform: "rpi0_2"},
      attrs
    )
  end

  describe "match/1" do
    test "matches a device to the image whose repo it was built from" do
      assert {:ok, "Circuits Quickstart", config} = Catalog.match(device())
      assert config.repo == "elixir-circuits/circuits_quickstart"
    end

    test "matches the other catalog images by the same rule" do
      assert {:ok, "Nerves Livebook", _} =
               Catalog.match(device(%{product: "nerves_livebook", platform: "rpi4"}))

      assert {:ok, "Nerves Web Kiosk Demo", _} =
               Catalog.match(device(%{product: "kiosk_demo", platform: "rpi4"}))
    end

    test "a product built from something else is not a catalog image" do
      assert Catalog.match(device(%{product: "my_custom_app"})) == :no_match
    end

    test "a device that advertises nothing cannot be matched" do
      assert Catalog.match(device(%{product: nil})) == :no_match
      assert Catalog.match(device(%{platform: nil})) == :no_match
    end

    test "serial devices are never matched, since OTA needs a network" do
      assert Catalog.match(device(%{type: :uart})) == :no_match
    end

    test "a target the image does not build is not a match" do
      assert Catalog.match(device(%{platform: "some_unknown_board"})) == :no_match
    end

    test "targets shipped only as a disk image cannot be updated over the air" do
      assert Catalog.match(device(%{platform: "grisp2"})) == :no_match
    end
  end

  describe "asset_name/2" do
    test "names the firmware asset for a target" do
      {:ok, _, config} = Catalog.match(device())
      assert Catalog.asset_name(config, "rpi0_2") == "circuits_quickstart_rpi0_2.fw"
    end
  end

  describe "default_password/1" do
    test "knows the documented login for each published image" do
      {:ok, _, quickstart} = Catalog.match(device())
      {:ok, _, livebook} = Catalog.match(device(%{product: "nerves_livebook", platform: "rpi4"}))

      assert Catalog.default_password(quickstart) == "circuits"
      assert Catalog.default_password(livebook) == "nerves"
    end

    test "knows the kiosk demo's login too" do
      {:ok, _, kiosk} = Catalog.match(device(%{product: "kiosk_demo", platform: "rpi4"}))

      assert Catalog.default_password(kiosk) == "kiosk"
    end
  end

  describe "password_for/1" do
    test "answers from what a device reports running" do
      assert Catalog.password_for(device()) == "circuits"
      assert Catalog.password_for(device(%{product: "nerves_livebook"})) == "nerves"
      assert Catalog.password_for(device(%{product: "kiosk_demo"})) == "kiosk"
    end

    test "ignores the board, since the password belongs to the image" do
      # grisp2 cannot be updated over the air, but it still has a login.
      assert Catalog.password_for(device(%{platform: "grisp2"})) == "circuits"
      assert Catalog.password_for(device(%{platform: "some_unknown_board"})) == "circuits"
    end

    test "offers nothing for a device running something else" do
      assert Catalog.password_for(device(%{product: "my_custom_app"})) == nil
      assert Catalog.password_for(device(%{product: nil})) == nil
      assert Catalog.password_for(nil) == nil
    end
  end

  test "updatable?/1 answers without the caller destructuring a match" do
    assert Catalog.updatable?(device())
    refute Catalog.updatable?(device(%{type: :uart}))
    refute Catalog.updatable?(device(%{product: "my_custom_app"}))
  end
end
