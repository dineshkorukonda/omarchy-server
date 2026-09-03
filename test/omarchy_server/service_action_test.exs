defmodule OmarchyServer.ServiceActionTest do
  use ExUnit.Case, async: true

  alias OmarchyServer.ServiceAction

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

      server = %OmarchyServer.Config.Server{
        id: "exec-cmd-direct",
        name: "Exec Cmd Test",
        host: "127.0.0.1",
        user: "test",
        checks: []
      }

      {:ok, pid} =
        OmarchyServer.ServerWorker.start_link(server,
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
      server = %OmarchyServer.Config.Server{
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
        OmarchyServer.ServerWorker.start_link(server,
          runner: runner,
          auto_connect: true,
          name: nil
        )

      Process.sleep(50)

      assert {:error, :not_connected} = GenServer.call(pid, {:exec_cmd, "echo hello"})
    end
  end
end
