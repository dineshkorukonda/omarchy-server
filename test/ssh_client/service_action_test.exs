defmodule SSHClient.ServiceActionTest do
  use ExUnit.Case, async: true

  alias SSHClient.ServiceAction

  describe "run/4 argument validation" do
    test "rejects unsupported action" do
      assert {:error, msg} = ServiceAction.run("s1", "nginx", "systemctl", "kill")
      assert msg =~ "unsupported action"
    end

    test "rejects unsupported type" do
      assert {:error, msg} = ServiceAction.run("s1", "myapp", "upstart", "restart")
      assert msg =~ "unsupported service type"
    end

    test "returns error when worker is not running" do
      assert {:error, _} =
               ServiceAction.run("nonexistent-worker-abc", "nginx", "systemctl", "restart")
    end
  end

  describe "exec_cmd handler on ServerWorker" do
    test "exec_cmd on connected worker delegates command to runner" do
      parent = self()

      runner = fn
        _server, :connect ->
          {:ok, :mock_conn}

        _server, {:exec, :mock_conn, cmd} ->
          # Send only the explicit "echo hello" command to the test, not probe commands
          if cmd == "echo hello", do: send(parent, {:cmd_received, cmd})
          {:ok, "OK\nexit_code:0", 0}

        _server, {:close, :mock_conn} ->
          :ok

        _server, {:poll, :mock_conn, _checks} ->
          {:ok, %{metrics: %{}, checks: %{}}}
      end

      server = %SSHClient.Config.Server{
        id: "exec-cmd-direct",
        name: "Exec Cmd Test",
        host: "127.0.0.1",
        user: "test",
        checks: []
      }

      {:ok, pid} =
        SSHClient.ServerWorker.start_link(server,
          runner: runner,
          auto_connect: true,
          name: nil
        )

      # Wait for connection to complete (auto_connect runs :connect continue)
      Process.sleep(50)

      result = GenServer.call(pid, {:exec_cmd, "echo hello"})
      assert {:ok, output} = result
      assert output =~ "OK"
      assert_received {:cmd_received, cmd}
      assert cmd == "echo hello"
    end

    test "exec_cmd returns error when not connected" do
      server = %SSHClient.Config.Server{
        id: "exec-cmd-disconnected",
        name: "Disconnected",
        host: "127.0.0.1",
        user: "test",
        checks: []
      }

      runner = fn
        _server, :connect -> {:error, :econnrefused}
        _server, _ -> {:error, :not_connected}
      end

      {:ok, pid} =
        SSHClient.ServerWorker.start_link(server,
          runner: runner,
          auto_connect: true,
          name: nil
        )

      Process.sleep(50)

      assert {:error, :not_connected} = GenServer.call(pid, {:exec_cmd, "echo hello"})
    end
  end

  describe "run/4 and get_logs/3 with worker resolution" do
    test "run/4 executes restart and stop on systemctl, docker, pm2" do
      parent = self()

      runner = fn
        _server, :connect ->
          {:ok, :mock_conn}

        _server, {:exec, :mock_conn, cmd} ->
          if not String.contains?(cmd, "softlevel") do
            send(parent, {:exec_called, cmd})
          end

          {:ok, "Success\nexit_code:0", 0}

        _server, {:close, :mock_conn} ->
          :ok

        _server, {:poll, :mock_conn, _checks} ->
          {:ok, %{metrics: %{}, checks: %{}}}
      end

      server = %SSHClient.Config.Server{
        id: "svc-action-srv-1",
        name: "Svc Action Srv",
        host: "127.0.0.1",
        user: "test",
        checks: []
      }

      {:ok, _pid} =
        SSHClient.ServerWorker.start_link(server,
          runner: runner,
          auto_connect: true
        )

      Process.sleep(50)

      for type <- ["systemctl", "docker", "pm2"], action <- ["restart", "stop"] do
        assert {:ok, out} = ServiceAction.run(server.id, "my-app", type, action)
        assert out =~ "Success"
        assert_received {:exec_called, cmd}
        assert cmd =~ type
        assert cmd =~ action
      end
    end

    test "get_logs/3 retrieves logs with and without unit" do
      parent = self()

      runner = fn
        _server, :connect ->
          {:ok, :mock_conn}

        _server, {:exec, :mock_conn, cmd} ->
          if not String.contains?(cmd, "softlevel") do
            send(parent, {:exec_logs, cmd})
          end

          {:ok, "systemd journal entries line 1\nline 2", 0}

        _server, {:close, :mock_conn} ->
          :ok

        _server, {:poll, :mock_conn, _checks} ->
          {:ok, %{metrics: %{}, checks: %{}}}
      end

      server = %SSHClient.Config.Server{
        id: "svc-logs-srv-1",
        name: "Logs Srv",
        host: "127.0.0.1",
        user: "test",
        checks: []
      }

      {:ok, _pid} =
        SSHClient.ServerWorker.start_link(server,
          runner: runner,
          auto_connect: true
        )

      Process.sleep(50)

      assert {:ok, out} = ServiceAction.get_logs(server.id, 20)
      assert out =~ "systemd journal"
      assert_received {:exec_logs, cmd}
      assert cmd =~ "journalctl -n 20"

      assert {:ok, out2} = ServiceAction.get_logs(server.id, 30, "nginx.service")
      assert out2 =~ "systemd journal"
      assert_received {:exec_logs, cmd2}
      assert cmd2 =~ "journalctl -u nginx.service -n 30"
    end
  end
end
