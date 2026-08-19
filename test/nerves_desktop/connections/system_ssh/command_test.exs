defmodule NervesDesktop.Connections.SystemSSH.CommandTest do
  # Not async: the PATH test below mutates process-wide environment.
  use ExUnit.Case, async: false

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

  test "prefers the base-system script over one earlier in PATH" do
    # Regression: the argument form is chosen by OS, so a util-linux `script`
    # shadowing Apple's on macOS would receive BSD-form arguments and die with
    # "failed to parse output limit size".
    dir = Path.join(System.tmp_dir!(), "nd-script-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    shadow = Path.join(dir, "script")
    File.write!(shadow, "#!/bin/sh\n")
    File.chmod!(shadow, 0o755)

    original_path = System.get_env("PATH")
    System.put_env("PATH", dir <> ":" <> original_path)

    on_exit(fn ->
      System.put_env("PATH", original_path)
      File.rm_rf!(dir)
    end)

    assert System.find_executable("script") == shadow

    {:ok, exe, _args} = Command.build({:unix, :darwin}, "root@host.local")
    assert exe == "/usr/bin/script"
  end

  test "falls back to PATH when there is no base-system script" do
    # Non-FHS hosts such as NixOS have no /usr/bin/script; the util-linux form
    # is still correct there because it is selected by OS, not by path.
    {:ok, _exe, args} = Command.build({:unix, :linux}, "root@host.local")
    assert ["-q", "-c", command, "/dev/null"] = args
    assert command =~ "root@host.local"
  end

  test "rejects targets that could break out of the shell command" do
    for evil <- ["root@host; rm -rf /", "root@host$(id)", "root@host `id`", "root@host|nc x 1"] do
      assert {:error, :invalid_target} = Command.build({:unix, :linux}, evil, "/usr/bin/script")
    end
  end
end
