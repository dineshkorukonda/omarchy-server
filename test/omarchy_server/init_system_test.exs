defmodule OmarchyServer.InitSystemTest do
  use ExUnit.Case, async: false

  alias OmarchyServer.InitSystem

  setup do
    InitSystem.clear_cache()
    :ok
  end

  describe "probe_command/0" do
    test "returns a valid shell probe command" do
      cmd = InitSystem.probe_command()
      assert is_binary(cmd)
      assert cmd =~ "systemd"
      assert cmd =~ "openrc"
      assert cmd =~ "sysvinit"
    end
  end

  describe "parse/1" do
    test "detects systemd" do
      assert InitSystem.parse("systemd\n") == :systemd
      assert InitSystem.parse("  systemd  ") == :systemd
    end

    test "detects openrc" do
      assert InitSystem.parse("openrc\n") == :openrc
      assert InitSystem.parse("OPENRC") == :openrc
    end

    test "detects sysvinit" do
      assert InitSystem.parse("sysvinit\n") == :sysvinit
      assert InitSystem.parse("SysVinit") == :sysvinit
    end

    test "falls back gracefully to unsupported when none match" do
      assert InitSystem.parse("unsupported\n") == :unsupported
      assert InitSystem.parse("busybox-init") == :unsupported
      assert InitSystem.parse("custom_daemon") == :unsupported
      assert InitSystem.parse("") == :unsupported
      assert InitSystem.parse(nil) == :unsupported
    end
  end

  describe "detect/2" do
    test "probes host with runner and returns detected init system" do
      runner = fn _cmd -> {:ok, "systemd\n", 0} end
      assert {:ok, :systemd} = InitSystem.detect(runner)
    end

    test "supports runner returning {:ok, stdout}" do
      runner = fn _cmd -> {:ok, "openrc\n"} end
      assert {:ok, :openrc} = InitSystem.detect(runner)
    end

    test "falls back gracefully to unsupported when probe outputs unrecognized string" do
      runner = fn _cmd -> {:ok, "unknown\n", 0} end
      assert {:ok, :unsupported} = InitSystem.detect(runner)
    end

    test "returns error when runner returns an error" do
      runner = fn _cmd -> {:error, :econnrefused} end
      assert {:error, :econnrefused} = InitSystem.detect(runner)
    end

    test "caches init system when server_id is provided" do
      call_count = :counters.new(1, [:atomics])

      runner = fn _cmd ->
        :counters.add(call_count, 1, 1)
        {:ok, "systemd\n", 0}
      end

      assert {:ok, :systemd} = InitSystem.detect(runner, "srv-1")
      assert :counters.get(call_count, 1) == 1

      # Second call with the same server_id should hit cache and not invoke runner
      assert {:ok, :systemd} = InitSystem.detect(runner, "srv-1")
      assert :counters.get(call_count, 1) == 1

      # Direct cache lookup
      assert {:ok, :systemd} = InitSystem.get_cached("srv-1")
    end
  end

  describe "cache management" do
    test "put_cached/2 and clear_cache/0" do
      assert InitSystem.get_cached("srv-manual") == :error
      assert :ok = InitSystem.put_cached("srv-manual", :openrc)
      assert {:ok, :openrc} = InitSystem.get_cached("srv-manual")

      assert :ok = InitSystem.clear_cache()
      assert InitSystem.get_cached("srv-manual") == :error
    end
  end
end
