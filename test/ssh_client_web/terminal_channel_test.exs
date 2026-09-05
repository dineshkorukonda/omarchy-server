defmodule SSHClientWeb.TerminalChannelTest do
  use ExUnit.Case, async: true

  alias SSHClientWeb.TerminalChannel

  test "join/3 succeeds for terminal topic with server_id and dimensions" do
    assert {:ok, resp, state} =
             TerminalChannel.join("terminal:prod-1", %{"cols" => 120, "rows" => 40})

    assert resp.status == "connected"
    assert resp.server_id == "prod-1"
    assert state.terminal.server_id == "prod-1"
    assert state.terminal.cols == 120
    assert state.terminal.rows == 40
  end

  test "join/3 rejects unauthorized topics" do
    assert {:error, %{reason: "unauthorized"}} = TerminalChannel.join("other:prod-1", %{})
  end

  test "handle_in pty:resize updates terminal dimensions" do
    state = %{terminal: %TerminalChannel{server_id: "demo", cols: 80, rows: 24}}

    assert {:reply, :ok, new_state} =
             TerminalChannel.handle_in("pty:resize", %{"cols" => 100, "rows" => 30}, state)

    assert new_state.terminal.cols == 100
    assert new_state.terminal.rows == 30
  end

  test "handle_pty_data and handle_pty_eof format channel push events" do
    assert {:push, "pty:output", %{data: "hello world"}} =
             TerminalChannel.handle_pty_data("hello world")

    assert {:push, "pty:closed", %{reason: "eof"}} = TerminalChannel.handle_pty_eof()
  end

  test "wrap_bracketed_paste wraps text with terminal paste delimiters" do
    wrapped = TerminalChannel.wrap_bracketed_paste("echo line1\necho line2")
    assert String.starts_with?(wrapped, "\e[200~")
    assert String.ends_with?(wrapped, "\e[201~")
    assert wrapped =~ "echo line1\necho line2"
  end
end
