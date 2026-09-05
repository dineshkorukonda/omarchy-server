defmodule SSHClientWeb.TerminalLiveTest do
  use ExUnit.Case, async: true

  alias SSHClientWeb.TerminalLive

  test "initial_state returns standard map structure with terminal defaults" do
    state = TerminalLive.initial_state(server_id: "prod-1", title: "prod-1")
    assert state.server_id == "prod-1"
    assert state.title == "prod-1"
    assert state.cols == 80
    assert state.rows == 24
    assert state.connected == false
    assert is_map(state.theme)
  end

  test "render_html returns xterm.js container element and script hook" do
    state = TerminalLive.initial_state(server_id: "demo", title: "Demo Host")
    html = TerminalLive.render_html(state)

    assert is_binary(html)
    assert html =~ "id=\"xterm-container\""
    assert html =~ "phx-hook=\"TerminalHook\""
    assert html =~ "data-cols=\"80\""
    assert html =~ "data-rows=\"24\""
    assert html =~ "Demo Host"
  end
end
