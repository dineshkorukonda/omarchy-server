defmodule SSHClient.ServiceChecksTest do
  use ExUnit.Case, async: true

  alias SSHClient.Config.Check
  alias SSHClient.ServiceChecks

  describe "build_command/2" do
    test "builds valid command for systemctl" do
      assert {:ok, cmd} = ServiceChecks.build_command(:systemctl, "nginx")
      assert cmd =~ "systemctl is-active"
      assert cmd =~ "nginx"
      assert cmd =~ "missing"
    end

    test "builds valid command for docker" do
      assert {:ok, cmd} = ServiceChecks.build_command(:docker, "redis-cache")
      assert cmd =~ "docker inspect"
      assert cmd =~ "redis-cache"
      assert cmd =~ "missing"
    end

    test "builds valid command for pm2" do
      assert {:ok, cmd} = ServiceChecks.build_command(:pm2, "api-app")
      assert cmd =~ "pm2 describe"
      assert cmd =~ "api-app"
      assert cmd =~ "missing"
    end

    test "returns error for unsupported check type" do
      assert {:error, message} = ServiceChecks.build_command(:unknown_tool, "test")
      assert message =~ "unsupported check type"
    end
  end

  describe "parse_status/1" do
    test "parses running status" do
      assert ServiceChecks.parse_status("running\n") == :running
      assert ServiceChecks.parse_status("RUNNING") == :running
    end

    test "parses stopped status" do
      assert ServiceChecks.parse_status("stopped\n") == :stopped
      assert ServiceChecks.parse_status("STOPPED") == :stopped
    end

    test "parses missing tool as skipped" do
      assert ServiceChecks.parse_status("missing\n") == :skipped
      assert ServiceChecks.parse_status("MISSING") == :skipped
    end

    test "parses unknown status" do
      assert ServiceChecks.parse_status("unknown\n") == :unknown
      assert ServiceChecks.parse_status("other_text") == :unknown
      assert ServiceChecks.parse_status("") == :unknown
      assert ServiceChecks.parse_status(nil) == :unknown
    end
  end

  describe "check/3" do
    test "returns running for active service" do
      check = %Check{type: :systemctl, name: "nginx"}
      runner = fn _cmd -> {:ok, "running\n", 0} end

      assert {:ok, :running} = ServiceChecks.check(check, runner)
    end

    test "returns stopped for inactive service" do
      check = %Check{type: :docker, name: "postgres"}
      runner = fn _cmd -> {:ok, "stopped\n", 0} end

      assert {:ok, :stopped} = ServiceChecks.check(check, runner)
    end

    test "returns skipped when tool is not installed, not an error" do
      check = %Check{type: :docker, name: "redis"}
      runner = fn _cmd -> {:ok, "missing\n", 0} end

      assert {:ok, :skipped} = ServiceChecks.check(check, runner)
    end

    test "returns error when runner fails" do
      check = %Check{type: :pm2, name: "app"}
      runner = fn _cmd -> {:error, :timeout} end

      assert {:error, :timeout} = ServiceChecks.check(check, runner)
    end
  end

  describe "check_all/3" do
    test "aggregates results across multiple check types and handles skipped tools" do
      checks = [
        %Check{type: :systemctl, name: "nginx"},
        %Check{type: :docker, name: "postgres"},
        %Check{type: :pm2, name: "worker"}
      ]

      runner = fn cmd ->
        cond do
          cmd =~ "nginx" -> {:ok, "running\n", 0}
          cmd =~ "postgres" -> {:ok, "stopped\n", 0}
          cmd =~ "worker" -> {:ok, "missing\n", 0}
        end
      end

      assert {:ok, results} = ServiceChecks.check_all(checks, runner)

      assert results["nginx"] == %{type: :systemctl, name: "nginx", status: :running}
      assert results["postgres"] == %{type: :docker, name: "postgres", status: :stopped}
      assert results["worker"] == %{type: :pm2, name: "worker", status: :skipped}
    end
  end
end
