defmodule NervesDesktop.Firmware.UploadTest do
  use ExUnit.Case, async: false

  alias NervesDesktop.Firmware.Upload

  setup do
    original = Application.get_env(:nerves_desktop, :ssh_client)
    on_exit(fn -> Application.put_env(:nerves_desktop, :ssh_client, original) end)
    :ok
  end

  test "uploads follow the SSH client chosen in Settings" do
    Application.put_env(:nerves_desktop, :ssh_client, :system_ssh)
    assert Upload.backend() == Upload.SystemSSH

    Application.put_env(:nerves_desktop, :ssh_client, :erlang_ssh)
    assert Upload.backend() == Upload.ErlangSSH
  end

  test "defaults to the built-in client when nothing is configured" do
    Application.delete_env(:nerves_desktop, :ssh_client)
    assert Upload.backend() == Upload.ErlangSSH
  end
end
