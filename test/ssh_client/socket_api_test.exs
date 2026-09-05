defmodule SSHClient.SocketAPITest do
  use ExUnit.Case, async: false

  alias SSHClient.Config.Server
  alias SSHClient.ServerManager
  alias SSHClient.SocketAPI

  @moduletag :unix_only

  setup do
    sock_path =
      Path.join(System.tmp_dir!(), "omarchy_uds_test_#{System.unique_integer([:positive])}.sock")

    on_exit(fn -> File.rm(sock_path) end)

    {:ok, socket_api} =
      start_supervised({SocketAPI, name: nil, socket_path: sock_path})

    # Add a mock server to ServerManager so state is non-empty
    test_server = %Server{
      id: "socket-test-node",
      name: "Socket Test Node",
      host: "10.0.0.99"
    }

    mock_runner = fn
      _server, :connect -> {:ok, :fake_conn}
      _server, {:exec, _conn, _cmd} -> {:ok, "systemd\n", 0}
      _server, {:poll, _conn, _checks} -> {:ok, %{metrics: %{cpu: 25}, checks: %{}}}
      _server, {:close, _conn} -> :ok
    end

    ServerManager.sync_config([test_server], runner: mock_runner)
    Process.sleep(50)

    %{socket_path: sock_path, socket_api: socket_api}
  end

  describe "Unix domain socket JSON API" do
    test "connects and reads JSON state using native gen_tcp", %{socket_path: sock_path} do
      {:ok, client} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      assert :ok = :gen_tcp.send(client, "GET\n")
      {:ok, data} = :gen_tcp.recv(client, 0, 1000)
      :gen_tcp.close(client)

      assert {:ok, json} = :json.decode(data) |> then(&{:ok, &1})
      assert json["status"] == "ok"
      assert is_list(json["servers"])
      assert json["count"] >= 1

      [node | _] = json["servers"]
      assert node["id"] == "socket-test-node"
      assert node["host"] == "10.0.0.99"
      assert node["status"] == "polling"
    end

    test "connects and reads JSON state using nc -U CLI command", %{socket_path: sock_path} do
      case System.find_executable("nc") do
        nil ->
          :ok

        nc_path ->
          {output, 0} = System.cmd(nc_path, ["-U", sock_path], stderr_to_stdout: true)

          assert {:ok, json} = :json.decode(output) |> then(&{:ok, &1})
          assert json["status"] == "ok"
          assert is_list(json["servers"])
          assert json["count"] >= 1
      end
    end

    test "handles get_server JSON command", %{socket_path: sock_path} do
      {:ok, client} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      req = ~s({"command": "get_server", "server_id": "socket-test-node"}\n)
      assert :ok = :gen_tcp.send(client, req)
      {:ok, data} = :gen_tcp.recv(client, 0, 1000)
      :gen_tcp.close(client)

      assert {:ok, json} = :json.decode(data) |> then(&{:ok, &1})
      assert json["status"] == "ok"
      assert json["server"]["id"] == "socket-test-node"
    end

    test "handles service_action command", %{socket_path: sock_path} do
      {:ok, client} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      req =
        ~s({"command": "service_action", "server_id": "socket-test-node", "service": "nginx", "type": "systemctl", "action": "restart"}\n)

      assert :ok = :gen_tcp.send(client, req)
      {:ok, data} = :gen_tcp.recv(client, 0, 1000)
      :gen_tcp.close(client)

      assert {:ok, json} = :json.decode(data) |> then(&{:ok, &1})
      assert json["status"] == "ok"
      assert json["service"] == "nginx"
      assert json["action"] == "restart"
    end

    test "handles get_logs command", %{socket_path: sock_path} do
      {:ok, client} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      req = ~s({"command": "get_logs", "server_id": "socket-test-node", "lines": 20}\n)

      assert :ok = :gen_tcp.send(client, req)
      {:ok, data} = :gen_tcp.recv(client, 0, 1000)
      :gen_tcp.close(client)

      assert {:ok, json} = :json.decode(data) |> then(&{:ok, &1})
      assert json["status"] == "ok"
      assert json["server_id"] == "socket-test-node"
      assert json["lines"] == 20
    end

    test "handles reload command", %{socket_path: sock_path} do
      {:ok, client} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      req = ~s({"command": "reload"}\n)

      assert :ok = :gen_tcp.send(client, req)
      {:ok, data} = :gen_tcp.recv(client, 0, 1000)
      :gen_tcp.close(client)

      assert {:ok, json} = :json.decode(data) |> then(&{:ok, &1})

      # reload attempts file sync (which may succeed or return error if file doesn't exist, but responds valid JSON)
      assert is_map(json)
      assert Map.has_key?(json, "status")
    end

    test "handles add_server and remove_server commands", %{socket_path: sock_path} do
      {:ok, client} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      add_req =
        ~s({"command": "add_server", "server": {"id": "sock-dyn-1", "host": "192.168.1.55", "port": 2222}}\n)

      assert :ok = :gen_tcp.send(client, add_req)
      {:ok, data} = :gen_tcp.recv(client, 0, 1000)
      :gen_tcp.close(client)

      assert {:ok, json} = :json.decode(data) |> then(&{:ok, &1})
      assert json["status"] == "ok"
      assert json["server"]["id"] == "sock-dyn-1"

      # Verify it appears in get_server
      {:ok, client2} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      get_req = ~s({"command": "get_server", "server_id": "sock-dyn-1"}\n)
      assert :ok = :gen_tcp.send(client2, get_req)
      {:ok, data2} = :gen_tcp.recv(client2, 0, 1000)
      :gen_tcp.close(client2)

      assert {:ok, json2} = :json.decode(data2) |> then(&{:ok, &1})
      assert json2["status"] == "ok"
      assert json2["server"]["id"] == "sock-dyn-1"

      # Remove server
      {:ok, client3} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      rem_req = ~s({"command": "remove_server", "server_id": "sock-dyn-1"}\n)
      assert :ok = :gen_tcp.send(client3, rem_req)
      {:ok, data3} = :gen_tcp.recv(client3, 0, 1000)
      :gen_tcp.close(client3)

      assert {:ok, json3} = :json.decode(data3) |> then(&{:ok, &1})
      assert json3["status"] == "ok"
    end

    test "handles poll_now and poll_all commands", %{socket_path: sock_path} do
      {:ok, client1} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      poll_req = ~s({"command": "poll_now", "server_id": "socket-test-node"}\n)
      assert :ok = :gen_tcp.send(client1, poll_req)
      {:ok, data1} = :gen_tcp.recv(client1, 0, 1000)
      :gen_tcp.close(client1)

      assert {:ok, json1} = :json.decode(data1) |> then(&{:ok, &1})
      assert json1["status"] == "ok"
      assert json1["server_id"] == "socket-test-node"
      assert json1["worker_status"] == "polling"

      {:ok, client2} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      poll_all_req = ~s({"command": "poll_all"}\n)
      assert :ok = :gen_tcp.send(client2, poll_all_req)
      {:ok, data2} = :gen_tcp.recv(client2, 0, 1000)
      :gen_tcp.close(client2)

      assert {:ok, json2} = :json.decode(data2) |> then(&{:ok, &1})
      assert json2["status"] == "ok"
      assert is_list(json2["servers"])
    end

    test "handles open_terminal command for unknown server", %{socket_path: sock_path} do
      {:ok, client} =
        :gen_tcp.connect({:local, String.to_charlist(sock_path)}, 0, [
          :binary,
          :local,
          active: false
        ])

      term_req =
        ~s({"command": "open_terminal", "server_id": "non-existent", "cols": 80, "rows": 24}\n)

      assert :ok = :gen_tcp.send(client, term_req)
      {:ok, data} = :gen_tcp.recv(client, 0, 1000)
      :gen_tcp.close(client)

      assert {:ok, json} = :json.decode(data) |> then(&{:ok, &1})
      assert json["status"] == "error"
      assert json["error"] =~ "server worker not found"
    end
  end
end
