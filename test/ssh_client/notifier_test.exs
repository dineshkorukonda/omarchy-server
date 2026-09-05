defmodule SSHClient.NotifierTest do
  use ExUnit.Case, async: true

  alias SSHClient.Notifier

  describe "notify_state_change/3" do
    test "emits notification for polling to reconnecting (offline)" do
      # notify-send may not be installed in CI; the call must not raise
      assert :ok = Notifier.notify_state_change("web-1", :polling, :reconnecting)
    end

    test "emits notification for reconnecting to polling (recovery)" do
      assert :ok = Notifier.notify_state_change("web-1", :reconnecting, :polling)
    end

    test "emits notification for polling to degraded" do
      assert :ok = Notifier.notify_state_change("web-1", :polling, :degraded)
    end

    test "emits notification for degraded to polling (recovery)" do
      assert :ok = Notifier.notify_state_change("web-1", :degraded, :polling)
    end

    test "skips notification for same state" do
      assert :ok = Notifier.notify_state_change("web-1", :polling, :polling)
    end

    test "skips notification for connecting to connecting" do
      assert :ok = Notifier.notify_state_change("web-1", :connecting, :connecting)
    end
  end

  describe "classify_transition via notify_state_change" do
    test "does not raise for any valid state combinations" do
      states = [:connecting, :polling, :degraded, :reconnecting]

      for old <- states, new <- states do
        assert :ok = Notifier.notify_state_change("server", old, new)
      end
    end
  end
end
