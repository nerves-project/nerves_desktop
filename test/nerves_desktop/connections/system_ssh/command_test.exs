defmodule NervesDesktop.Connections.SystemSSH.CommandTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Connections.SystemSSH.Command

  test "uses the bsd argument form on darwin" do
    {:ok, exe, args} = Command.build({:unix, :darwin}, "root@host.local", "/usr/bin/script")
    assert exe == "/usr/bin/script"
    assert ["-q", "/dev/null", "ssh" | _] = args
    assert List.last(args) == "root@host.local"
  end

  test "uses the util-linux argument form on linux" do
    {:ok, _exe, args} = Command.build({:unix, :linux}, "root@host.local", "/usr/bin/script")
    assert ["-q", "-c", command, "/dev/null"] = args
    assert command =~ "ssh "
    assert command =~ "root@host.local"
  end

  test "is unsupported on windows" do
    assert {:error, :unsupported_os} =
             Command.build({:win32, :nt}, "root@host.local", "C:\\script.exe")
  end

  test "reports a missing script executable" do
    assert {:error, :script_not_found} = Command.build({:unix, :linux}, "root@host.local", nil)
  end

  test "rejects targets that could break out of the shell command" do
    for evil <- ["root@host; rm -rf /", "root@host$(id)", "root@host `id`", "root@host|nc x 1"] do
      assert {:error, :invalid_target} = Command.build({:unix, :linux}, evil, "/usr/bin/script")
    end
  end
end
