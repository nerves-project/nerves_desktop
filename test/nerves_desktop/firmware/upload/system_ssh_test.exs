defmodule NervesDesktop.Firmware.Upload.SystemSSHTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Firmware.Upload.SystemSSH

  test "pipes the archive into the fwup subsystem" do
    {:ok, exe, args} = SystemSSH.build("nerves-3671.local", "/tmp/fw.fw")

    assert exe == "/bin/sh"
    assert ["-c", script, "/tmp/fw.fw", "root@nerves-3671.local"] = args
    assert script =~ "cat"
    assert script =~ "ssh"
    assert script =~ "fwup"
  end

  test "passes the path and host as arguments so neither is interpolated" do
    # A hostname carrying shell metacharacters must reach ssh as one opaque
    # word rather than becoming part of the command.
    {:ok, _exe, args} = SystemSSH.build("host; rm -rf /", "/tmp/fw.fw")

    assert ["-c", script, "/tmp/fw.fw", "root@host; rm -rf /"] = args
    refute script =~ "rm -rf"
  end

  test "reads the archive through $0 and the host through $1" do
    {:ok, _exe, ["-c", script, _path, _host]} = SystemSSH.build("h", "/tmp/fw.fw")

    assert script =~ ~S($0)
    assert script =~ ~S($1)
  end

  test "does not verify host keys, since reflashing a device changes them" do
    {:ok, _exe, ["-c", script, _, _]} = SystemSSH.build("h", "/tmp/fw.fw")

    assert script =~ "StrictHostKeyChecking=no"
  end

  test "reports a missing ssh binary rather than failing at spawn time" do
    assert {:error, :ssh_not_found} = SystemSSH.build("h", "/tmp/fw.fw", nil)
  end
end
