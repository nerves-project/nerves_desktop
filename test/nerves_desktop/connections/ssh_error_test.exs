defmodule NervesDesktop.Connections.SSHErrorTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Connections.SSHError

  # Reasons below were captured from real :ssh.connect/4 failures against a Nerves device.
  @auth_failed ~c"Unable to connect using the available authentication methods"
  @refused ~c"Service not available"

  describe "when no password was entered" do
    test "asks for the password instead of blaming key passphrases" do
      message = SSHError.describe(@refused, target: "nerves.local", password?: false)

      assert message =~ "nerves.local"
      assert message =~ "password"
      refute message =~ "passphrase-protected key" and message =~ "cannot decrypt"
    end

    test "asks for the password when no auth method succeeded" do
      message = SSHError.describe(@auth_failed, target: "nerves.local", password?: false)
      assert message =~ "password"
    end
  end

  describe "when a password was entered" do
    test "says the password was rejected" do
      message = SSHError.describe(@auth_failed, target: "nerves.local", password?: true)

      assert message =~ "rejected the password"
      refute message =~ "SSH key"
    end

    test "does not claim the password is missing when the server refuses" do
      message = SSHError.describe(@refused, target: "nerves.local", password?: true)
      refute message =~ "Enter the device password"
    end
  end

  describe "network failures" do
    test "explains a host that cannot be resolved" do
      message = SSHError.describe(:nxdomain, target: "nerves.local", password?: false)

      assert message =~ "nerves.local"
      assert message =~ "network"
      refute message =~ "password"
    end

    test "explains a refused connection" do
      message = SSHError.describe(:econnrefused, target: "nerves.local", password?: false)

      assert message =~ "SSH"
      refute message =~ "password"
    end

    test "explains a timeout" do
      assert SSHError.describe(:etimedout, target: "nerves.local", password?: false) =~
               "Timed out"
    end
  end

  describe "system ssh setup failures" do
    test "explains a missing script command" do
      message = SSHError.describe(:script_not_found, target: "nerves.local", password?: false)

      assert message =~ "script"
      assert message =~ "Erlang SSH"
      refute message =~ ":script_not_found"
    end

    test "explains an unsupported platform" do
      message = SSHError.describe(:unsupported_os, target: "nerves.local", password?: false)

      assert message =~ "Erlang SSH"
      refute message =~ ":unsupported_os"
    end

    test "explains a rejected target" do
      message = SSHError.describe(:invalid_target, target: "bad;host", password?: false)

      assert message =~ "bad;host"
      refute message =~ ":invalid_target"
    end
  end

  test "falls back to the raw reason when it is not recognised" do
    message = SSHError.describe(~c"some novel failure", target: "nerves.local", password?: false)
    assert message =~ "some novel failure"
  end
end
