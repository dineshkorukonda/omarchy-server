defmodule SSHClientWeb.TerminalLiveTest do
  use ExUnit.Case, async: true

  # TerminalLive is now a proper Phoenix LiveView.
  # Unit-level tests verify module compilation and basic facts.
  # Full LiveView integration tests require Phoenix.ConnCase / LiveViewTest
  # which will be wired up as the test suite matures.

  test "module is defined and compiled" do
    assert Code.ensure_loaded?(SSHClientWeb.TerminalLive)
  end
end
