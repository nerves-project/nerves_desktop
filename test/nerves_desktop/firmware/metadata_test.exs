defmodule NervesDesktop.Firmware.MetadataTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Firmware.Metadata

  @output """
  meta-product=circuits_quickstart
  meta-version=0.16.2
  meta-author="The Nerves Team"
  meta-platform=rpi0_2
  meta-architecture=aarch64
  meta-creation-date="2020-10-21T20:07:08Z"
  meta-uuid="7e2ab1b1-1882-5841-7382-ad4ada05a00d"
  meta-nickname="loop-chalk"
  """

  test "reads the fields we compare on" do
    assert {:ok, meta} = Metadata.parse(@output)

    assert meta.product == "circuits_quickstart"
    assert meta.version == "0.16.2"
    assert meta.platform == "rpi0_2"
    assert meta.uuid == "7e2ab1b1-1882-5841-7382-ad4ada05a00d"
  end

  test "strips the quotes fwup puts around some values but not others" do
    assert {:ok, meta} = Metadata.parse(@output)

    refute meta.uuid =~ ~s(")
    refute meta.version =~ ~s(")
  end

  test "fields fwup did not emit come back nil rather than missing" do
    assert {:ok, meta} = Metadata.parse("meta-product=kiosk_demo\n")

    assert meta.product == "kiosk_demo"
    assert meta.version == nil
    assert meta.platform == nil
    assert meta.uuid == nil
  end

  test "ignores lines that are not metadata" do
    output = "fwup: warning: truncated archive\nmeta-uuid=\"abc\"\n"

    assert {:ok, %{uuid: "abc"}} = Metadata.parse(output)
  end

  test "output with no metadata at all is an error, not an empty struct" do
    assert Metadata.parse("fwup: error: bad file\n") == {:error, :no_metadata}
    assert Metadata.parse("") == {:error, :no_metadata}
  end
end
