defmodule OmarchyServer.SocketAPITest do
  use ExUnit.Case, async: false

  alias OmarchyServer.Config.Server
  alias OmarchyServer.ServerManager
  alias OmarchyServer.SocketAPI

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
  end
end
