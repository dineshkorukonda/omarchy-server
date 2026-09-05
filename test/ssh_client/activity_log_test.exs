defmodule SSHClient.ActivityLogTest do
  use ExUnit.Case, async: false

  alias SSHClient.ActivityLog

  setup do
    ActivityLog.clear()
    :ok
  end

  describe "log/4 and list_logs/1" do
    test "records and retrieves log entries with newest first" do
      ActivityLog.info("server-1", "First event")
      ActivityLog.warn("server-2", "Second event", %{reason: :slow})
      ActivityLog.error("server-1", "Third event", "Fatal error")

      logs = ActivityLog.list_logs()
      assert length(logs) == 3

      [entry1, entry2, entry3] = logs
      assert entry1.message == "Third event"
      assert entry1.level == :error
      assert entry1.server_id == "server-1"
      assert entry1.details =~ "Fatal error"

      assert entry2.message == "Second event"
      assert entry2.level == :warn

      assert entry3.message == "First event"
      assert entry3.level == :info
    end

    test "filters by log level" do
      ActivityLog.info("srv", "Info message")
      ActivityLog.error("srv", "Error message")

      info_logs = ActivityLog.list_logs(level: :info)
      assert length(info_logs) == 1
      assert hd(info_logs).message == "Info message"

      error_logs = ActivityLog.list_logs(level: :error)
      assert length(error_logs) == 1
      assert hd(error_logs).message == "Error message"
    end

    test "filters by server_id" do
      ActivityLog.info("srv-a", "Msg A")
      ActivityLog.info("srv-b", "Msg B")

      logs_a = ActivityLog.list_logs(server_id: "srv-a")
      assert length(logs_a) == 1
      assert hd(logs_a).message == "Msg A"
    end

    test "clear/0 removes all stored logs" do
      ActivityLog.info("srv", "To be cleared")
      assert length(ActivityLog.list_logs()) == 1

      ActivityLog.clear()
      assert ActivityLog.list_logs() == []
    end

    test "subscribe/0 notifies caller on new log entry" do
      ActivityLog.subscribe()
      ActivityLog.warn("srv-x", "Subscribed alert")

      assert_receive {:new_log_entry, entry}, 1000
      assert entry.message == "Subscribed alert"
      assert entry.level == :warn
    end
  end
end
