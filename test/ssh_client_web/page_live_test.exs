defmodule SSHClientWeb.PageLiveTest do
  use ExUnit.Case, async: true

  alias SSHClient.Window
  alias SSHClientWeb.PageLive

  test "detects runtime operating system" do
    os = PageLive.detect_os()
    assert is_binary(os)
    assert os =~ "Windows" or os =~ "Linux" or os =~ "macOS" or os =~ "Unknown"
  end

  test "provides initial desktop page state" do
    state = PageLive.initial_state()
    assert state.page_title == "ssh-client"
    assert state.app_status == :ready
    assert state.version == "0.2.0"
  end

  test "Window child_spec is valid OTP worker" do
    spec = Window.child_spec([])
    assert spec.id == Window
    assert spec.type == :worker
  end
end
