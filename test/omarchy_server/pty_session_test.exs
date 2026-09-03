defmodule OmarchyServer.PTYSessionTest do
  use ExUnit.Case, async: false

  alias OmarchyServer.Config.Server
  alias OmarchyServer.SSH
  alias OmarchyServer.TerminalSupervisor

  setup do
    test_server = %Server{
      id: "pty-test-node",
      name: "PTY Test Node",
      host: "127.0.0.1",
      port: 2222
    }

    %{server: test_server}
  end

  describe "PTYSession lifecycle and supervision" do
    test "TerminalSupervisor starts child and handles connection failure gracefully", %{
      server: server
    } do
      # Since 127.0.0.1:2222 is not running SSH in unit test, connection fails gracefully
      assert {:ok, session_pid} =
               TerminalSupervisor.start_session(server, client_pid: self())

      assert_receive {:pty_error, _reason}, 2000
      ref = Process.monitor(session_pid)
      assert_receive {:DOWN, ^ref, :process, ^session_pid, _}, 2000
    end

    test "SSH.open_pty returns error tuple on invalid connection" do
      fake_conn = %SSH.Connection{conn_ref: :invalid_ref}
      assert {:error, {:pty_failed, _}} = SSH.open_pty(fake_conn)
    end

    test "SSH.send_pty_data returns error on dead connection" do
      fake_conn = %SSH.Connection{conn_ref: :invalid_ref}
      assert {:error, {:send_failed, _}} = SSH.send_pty_data(fake_conn, 1, "test")
    end

    test "SSH.close_pty handles closed channel safely" do
      fake_conn = %SSH.Connection{conn_ref: :invalid_ref}
      assert :ok = SSH.close_pty(fake_conn, 1)
    end
  end
end
