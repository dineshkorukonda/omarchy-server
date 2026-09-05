defmodule SSHClient.MetricsTest do
  use ExUnit.Case, async: true

  alias SSHClient.Metrics

  @top_fixture File.read!("test/fixtures/metrics/top_standard.txt")
  @free_fixture File.read!("test/fixtures/metrics/free_standard.txt")
  @df_fixture File.read!("test/fixtures/metrics/df_standard.txt")

  describe "parse_top/1" do
    test "parses CPU metrics and load averages from standard top output" do
      assert {:ok, cpu} = Metrics.parse_top(@top_fixture)

      assert cpu.user == 31.1
      assert cpu.system == 2.0
      assert cpu.idle == 65.8
      assert cpu.used_percent == 34.2
      assert cpu.load_1 == 6.65
      assert cpu.load_5 == 6.02
      assert cpu.load_15 == 5.15
    end

    test "parses busybox top CPU format" do
      busybox_top = """
      Mem: 243200K used, 269784K free, 1316K shrd, 21852K buff, 107640K cached
      CPU:  15% usr   5% sys   0% nic  80% idle   0% io
      Load average: 0.12 0.08 0.05
      """

      assert {:ok, cpu} = Metrics.parse_top(busybox_top)
      assert cpu.user == 15.0
      assert cpu.system == 5.0
      assert cpu.idle == 80.0
      assert cpu.used_percent == 20.0
      assert cpu.load_1 == 0.12
      assert cpu.load_5 == 0.08
      assert cpu.load_15 == 0.05
    end

    test "returns error on invalid top output" do
      assert {:error, _} = Metrics.parse_top("invalid output with no cpu line")
    end
  end

  describe "parse_free/1" do
    test "parses memory metrics from standard free -m output" do
      assert {:ok, mem} = Metrics.parse_free(@free_fixture)

      assert mem.total_mb == 15210
      assert mem.used_mb == 5595
      assert mem.free_mb == 4469
      assert mem.available_mb == 9614
      assert mem.used_percent == 36.8
    end

    test "parses legacy Linux free output" do
      legacy_free = """
                   total       used       free     shared    buffers     cached
      Mem:          4000       2000       2000          0        200        800
      -/+ buffers/cache:       1000       3000
      Swap:         2000          0       2000
      """

      assert {:ok, mem} = Metrics.parse_free(legacy_free)
      assert mem.total_mb == 4000
      assert mem.used_mb == 2000
      assert mem.available_mb == 3000
      assert mem.used_percent == 25.0
    end

    test "returns error on invalid free output" do
      assert {:error, _} = Metrics.parse_free("no memory line found")
    end
  end

  describe "parse_df/1" do
    test "parses disk mounts and identifies root disk" do
      assert {:ok, disk} = Metrics.parse_df(@df_fixture)

      assert length(disk.disks) == 4

      assert disk.root.mount == "/"
      assert disk.root.filesystem == "/dev/mapper/omarchy_root"
      assert disk.root.size == "126G"
      assert disk.root.used == "25G"
      assert disk.root.avail == "100G"
      assert disk.root.use_percent == 20
    end

    test "returns error when no valid filesystem lines exist" do
      assert {:error, _} = Metrics.parse_df("Filesystem Size Used Avail Use% Mounted on\n")
    end
  end

  describe "parse_combined/1 and collect/2" do
    test "parses full combined output correctly" do
      combined =
        "#{@top_fixture}\n===OMARCHY_FREE===\n#{@free_fixture}\n===OMARCHY_DF===\n#{@df_fixture}"

      assert {:ok, metrics} = Metrics.parse_combined(combined)
      assert metrics.cpu.used_percent == 34.2
      assert metrics.memory.used_percent == 36.8
      assert metrics.disk.root.use_percent == 20
    end

    test "collect/2 executes command with runner function" do
      combined =
        "#{@top_fixture}\n===OMARCHY_FREE===\n#{@free_fixture}\n===OMARCHY_DF===\n#{@df_fixture}"

      runner = fn cmd ->
        assert cmd =~ "top"
        assert cmd =~ "free"
        assert cmd =~ "df"
        {:ok, combined, 0}
      end

      assert {:ok, metrics} = Metrics.collect(runner)
      assert is_map(metrics.cpu)
      assert is_map(metrics.memory)
      assert is_map(metrics.disk)
    end

    test "collect/2 handles runner errors gracefully" do
      runner = fn _cmd -> {:error, :timeout} end
      assert {:error, {:metrics_collection_failed, :timeout}} = Metrics.collect(runner)
    end

    test "parse_combined handles missing sections" do
      assert {:error, msg1} = Metrics.parse_combined("missing delimiter")
      assert msg1 =~ "failed to locate free section"

      assert {:error, msg2} = Metrics.parse_combined("header\n===OMARCHY_FREE===\nno df section")
      assert msg2 =~ "failed to locate disk section"
    end
  end
end
