defmodule SSHClientWeb.LiveViewsTest do
  use ExUnit.Case, async: true

  test "live view modules compile and load successfully" do
    assert Code.ensure_loaded?(SSHClientWeb.HostLive)
    assert Code.ensure_loaded?(SSHClientWeb.TerminalLive)
    assert Code.ensure_loaded?(SSHClientWeb.SettingsLive)
    assert Code.ensure_loaded?(SSHClientWeb.LogsLive)
  end
end
