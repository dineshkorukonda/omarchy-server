defmodule SSHClientWeb.PageLiveTest do
  use ExUnit.Case, async: true

  alias SSHClient.Window
  alias SSHClientWeb.PageLive

  test "detects runtime operating system" do
    os = PageLive.detect_os()
    assert is_binary(os)
    assert os =~ "Windows" or os =~ "Linux" or os =~ "macOS" or os =~ "Unknown"
  end

  test "Window child_spec is valid OTP worker" do
    spec = Window.child_spec([])
    assert spec.id == Window
    assert spec.type == :worker
  end
end
