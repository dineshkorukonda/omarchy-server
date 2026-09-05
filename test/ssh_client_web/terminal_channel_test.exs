defmodule SSHClientWeb.TerminalChannelTest do
  use ExUnit.Case, async: true

  alias SSHClientWeb.TerminalChannel

  test "wrap_bracketed_paste wraps text with terminal paste delimiters" do
    wrapped = TerminalChannel.wrap_bracketed_paste("echo line1\necho line2")
    assert String.starts_with?(wrapped, "\e[200~")
    assert String.ends_with?(wrapped, "\e[201~")
    assert wrapped =~ "echo line1\necho line2"
  end
end
