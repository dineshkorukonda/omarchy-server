defmodule SSHClient.HostTest do
  use ExUnit.Case, async: true

  alias SSHClient.Host

  describe "parse_quick_add/2" do
    test "parses user@host:port" do
      assert {:ok, host} = Host.parse_quick_add("deploy@192.168.1.50:2222")
      assert host.user == "deploy"
      assert host.address == "192.168.1.50"
      assert host.port == 2222
      assert host.name == "192.168.1.50"
    end

    test "parses user@host (defaults port to 22)" do
      assert {:ok, host} = Host.parse_quick_add("admin@server.example.com")
      assert host.user == "admin"
      assert host.address == "server.example.com"
      assert host.port == 22
    end

    test "parses bare host" do
      assert {:ok, host} = Host.parse_quick_add("router.internal")
      assert host.address == "router.internal"
      assert host.port == 22
      assert is_binary(host.user)
    end

    test "parses ssh command style syntax with -p port flag" do
      assert {:ok, host} = Host.parse_quick_add("ssh ubuntu@ec2.aws.com -p 2200")
      assert host.user == "ubuntu"
      assert host.address == "ec2.aws.com"
      assert host.port == 2200
    end

    test "respects options overrides for name, jump_host, and group" do
      assert {:ok, host} =
               Host.parse_quick_add("root@10.0.0.1",
                 name: "DB Master",
                 group: "Production",
                 jump_host: "bastion.internal:22"
               )

      assert host.name == "DB Master"
      assert host.group == "Production"
      assert host.jump_host == "bastion.internal:22"
    end

    test "returns error for empty or invalid input" do
      assert {:error, _} = Host.parse_quick_add("")
      assert {:error, _} = Host.parse_quick_add("   ")
    end
  end
end
