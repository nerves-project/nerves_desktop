defmodule NervesDesktop.ConnectionTest do
  use ExUnit.Case, async: true

  alias NervesDesktop.Connection
  alias NervesDesktop.Connections.{ErlangSSH, SystemSSH, UART}

  test "uart devices always use the uart backend" do
    assert Connection.backend_for(%{type: :uart}, :system_ssh, {:unix, :darwin}) == UART
    assert Connection.backend_for(%{type: :uart}, :erlang_ssh, {:win32, :nt}) == UART
  end

  test "system ssh is honoured on unix" do
    assert Connection.backend_for(%{type: :network}, :system_ssh, {:unix, :linux}) == SystemSSH
  end

  test "windows falls back to erlang ssh even when system ssh is configured" do
    assert Connection.backend_for(%{type: :network}, :system_ssh, {:win32, :nt}) == ErlangSSH
  end

  test "erlang ssh is the default backend" do
    assert Connection.backend_for(%{type: :network}, :erlang_ssh, {:unix, :darwin}) == ErlangSSH
  end
end
