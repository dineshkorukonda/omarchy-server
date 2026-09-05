defmodule SSHClient.SSHTest do
  use ExUnit.Case, async: true

  alias SSHClient.Config.Server
  alias SSHClient.SSH
  alias SSHClient.SSH.Connection

  describe "parse_proxy_jump/1" do
    test "returns nil for nil or empty string" do
      assert SSH.parse_proxy_jump(nil) == nil
      assert SSH.parse_proxy_jump("") == nil
    end

    test "parses hostname only" do
      assert SSH.parse_proxy_jump("jump.internal") == %{
               host: "jump.internal",
               port: 22,
               user: nil
             }
    end

    test "parses user@hostname" do
      assert SSH.parse_proxy_jump("deploy@jump.internal") == %{
               host: "jump.internal",
               port: 22,
               user: "deploy"
             }
    end

    test "parses user@hostname:port" do
      assert SSH.parse_proxy_jump("deploy@jump.internal:2222") == %{
               host: "jump.internal",
               port: 2222,
               user: "deploy"
             }
    end

    test "parses hostname:port without user" do
      assert SSH.parse_proxy_jump("jump.internal:2222") == %{
               host: "jump.internal",
               port: 2222,
               user: nil
             }
    end
  end

  describe "connect/2 typed error handling" do
    test "returns typed error when target host is unreachable" do
      server = %Server{
        id: "unreachable",
        host: "127.0.0.1",
        port: 59999
      }

      assert {:error, {:connection_failed, _reason}} = SSH.connect(server, timeout: 500)
    end

    test "returns typed error when jump host connection fails" do
      server = %Server{
        id: "target",
        host: "10.0.0.1",
        port: 22,
        proxy_jump: "127.0.0.1:59999"
      }

      assert {:error, {:jump_host_failed, _reason}} = SSH.connect(server, timeout: 500)
    end
  end

  describe "collect_output/3" do
    test "accumulates stdout chunks and captures exit status" do
      conn_ref = make_ref()
      channel_id = 0

      send(self(), {:ssh_cm, conn_ref, {:data, channel_id, 0, "hello "}})
      send(self(), {:ssh_cm, conn_ref, {:data, channel_id, 0, "world\n"}})
      send(self(), {:ssh_cm, conn_ref, {:exit_status, channel_id, 0}})
      send(self(), {:ssh_cm, conn_ref, {:eof, channel_id}})
      send(self(), {:ssh_cm, conn_ref, {:closed, channel_id}})

      assert {:ok, "hello world\n", 0} = SSH.collect_output(conn_ref, channel_id, 1000)
    end

    test "captures non-zero exit status" do
      conn_ref = make_ref()
      channel_id = 1

      send(self(), {:ssh_cm, conn_ref, {:data, channel_id, 0, "error: not found\n"}})
      send(self(), {:ssh_cm, conn_ref, {:exit_status, channel_id, 127}})
      send(self(), {:ssh_cm, conn_ref, {:closed, channel_id}})

      assert {:ok, "error: not found\n", 127} = SSH.collect_output(conn_ref, channel_id, 1000)
    end

    test "times out when closed message is not received" do
      conn_ref = make_ref()
      channel_id = 2

      assert {:error, :timeout} = SSH.collect_output(conn_ref, channel_id, 50)
    end
  end

  describe "close/1" do
    test "handles connection struct gracefully" do
      conn = %Connection{conn_ref: nil, jump_ref: nil}
      assert :ok = SSH.close(conn)
      assert :ok = SSH.close(nil)
    end
  end

  describe "run/3" do
    test "returns connection failure without crashing" do
      assert {:error, {:connection_failed, _}} =
               SSH.run(%{host: "127.0.0.1", port: 59999}, "uptime", timeout: 200)
    end
  end
end
