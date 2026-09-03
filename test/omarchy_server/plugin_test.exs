defmodule OmarchyServer.PluginTest do
  use ExUnit.Case, async: true

  @manifest_path Path.expand("../../manifest.json", __DIR__)
  @panel_path Path.expand("../../Panel.qml", __DIR__)
  @model_path Path.expand("../../Model.js", __DIR__)

  describe "plugin manifest schema" do
    test "manifest.json exists and satisfies Omarchy plugin schema" do
      assert File.exists?(@manifest_path)
      content = File.read!(@manifest_path)
      assert {:ok, manifest} = :json.decode(content) |> then(&{:ok, &1})

      assert manifest["schemaVersion"] == 1
      assert manifest["id"] == "omarchy-server"
      assert manifest["name"] == "Servers"
      assert manifest["kinds"] == ["bar-widget"]

      # Entry point checks
      assert is_map(manifest["entryPoints"])
      assert manifest["entryPoints"]["barWidget"] == "Panel.qml"
      assert File.exists?(@panel_path)
      assert File.exists?(@model_path)

      # Bar widget section configuration
      assert is_map(manifest["barWidget"])
      assert manifest["barWidget"]["defaultSection"] in ["left", "center", "right"]
    end

    test "validates with omarchy-plugin-validate CLI tool" do
      validate_cli = System.find_executable("omarchy-plugin-validate")

      if validate_cli do
        tmp = Path.join(System.tmp_dir!(), "plugin_val_#{System.unique_integer([:positive])}")
        File.mkdir_p!(tmp)

        on_exit(fn -> File.rm_rf(tmp) end)

        File.cp!(@manifest_path, Path.join(tmp, "manifest.json"))
        File.cp!(@panel_path, Path.join(tmp, "Panel.qml"))
        File.cp!(@model_path, Path.join(tmp, "Model.js"))

        {_out, 0} = System.cmd(validate_cli, [tmp], stderr_to_stdout: true)
      end
    end
  end

  describe "Model.js logic" do
    test "parses server statuses and calculates health counts" do
      node_script = """
      const fs = require('fs');
      const vm = require('vm');
      const code = fs.readFileSync('#{@model_path}', 'utf8');
      const context = {};
      vm.createContext(context);
      vm.runInContext(code, context);

      const sample = JSON.stringify({
        status: 'ok',
        servers: [
          { id: 's1', status: 'polling' },
          { id: 's2', status: 'degraded' },
          { id: 's3', status: 'reconnecting' }
        ]
      });

      const parsed = context.parseStatus(sample);
      console.log(JSON.stringify(parsed));
      """

      node = System.find_executable("node")

      if node do
        {output, 0} = System.cmd(node, ["-e", node_script])
        {:ok, result} = :json.decode(String.trim(output)) |> then(&{:ok, &1})

        assert result["ok"] == true
        assert result["count"] == 3
        assert result["healthyCount"] == 1
        assert result["degradedCount"] == 1
        assert result["offlineCount"] == 1
        assert result["worstState"] == "offline"
      end
    end

    test "worstState prioritizes offline over degraded and degraded over polling" do
      node_script = """
      const fs = require('fs');
      const vm = require('vm');
      const code = fs.readFileSync('#{@model_path}', 'utf8');
      const context = {};
      vm.createContext(context);
      vm.runInContext(code, context);

      const allHealthy = context.worstState([{ status: 'polling' }, { status: 'polling' }]);
      const oneDegraded = context.worstState([{ status: 'polling' }, { status: 'degraded' }]);
      const oneOffline = context.worstState([{ status: 'polling' }, { status: 'degraded' }, { status: 'reconnecting' }]);
      const empty = context.worstState([]);

      const colors = { accent: '#22c55e', warning: '#f59e0b', urgent: '#ef4444', dim: '#9ca3af' };
      const green = context.statusColor(allHealthy, colors);
      const yellow = context.statusColor(oneDegraded, colors);
      const red = context.statusColor(oneOffline, colors);

      console.log(JSON.stringify({ allHealthy, oneDegraded, oneOffline, empty, green, yellow, red }));
      """

      node = System.find_executable("node")

      if node do
        {output, 0} = System.cmd(node, ["-e", node_script])
        {:ok, result} = :json.decode(String.trim(output)) |> then(&{:ok, &1})

        assert result["allHealthy"] == "polling"
        assert result["oneDegraded"] == "degraded"
        assert result["oneOffline"] == "offline"
        assert result["empty"] == "empty"

        assert result["green"] == "#22c55e"
        assert result["yellow"] == "#f59e0b"
        assert result["red"] == "#ef4444"
      end
    end

    test "formats metrics and finds selected server" do
      node_script = """
      const fs = require('fs');
      const vm = require('vm');
      const code = fs.readFileSync('#{@model_path}', 'utf8');
      const context = {};
      vm.createContext(context);
      vm.runInContext(code, context);

      const servers = [
        {
          id: 'web-1',
          name: 'Web Server 1',
          status: 'polling',
          metrics: {
            cpu: { used_percent: 18.5, load_1: 0.45, load_5: 0.32, load_15: 0.20 },
            memory: { used_mb: 4096, total_mb: 16384, used_percent: 25.0 },
            disk: { root: { used: '25G', size: '120G', use_percent: 21 } }
          },
          checks: {
            nginx: { name: 'nginx', type: 'systemctl', status: 'running' },
            app: { name: 'app', type: 'docker', status: 'stopped' }
          }
        }
      ];

      const found = context.findServer(servers, 'web-1');
      const notFound = context.findServer(servers, 'unknown');
      const cpu = context.formatCpu(found.metrics);
      const load = context.formatLoad(found.metrics);
      const mem = context.formatMem(found.metrics);
      const disk = context.formatDisk(found.metrics);
      const services = context.serviceList(found.checks);

      console.log(JSON.stringify({ foundId: found ? found.id : null, notFound, cpu, load, mem, disk, servicesCount: services.length }));
      """

      node = System.find_executable("node")

      if node do
        {output, 0} = System.cmd(node, ["-e", node_script])
        {:ok, result} = :json.decode(String.trim(output)) |> then(&{:ok, &1})

        assert result["foundId"] == "web-1"
        assert result["notFound"] in [nil, :null]
        assert result["cpu"] == "18.5%"
        assert result["load"] == "0.45, 0.32, 0.2"
        assert result["mem"] == "4096 / 16384 MB (25%)"
        assert result["disk"] == "25G / 120G (21%)"
        assert result["servicesCount"] == 2
      end
    end

    test "buildSshCommand assembles ssh argv from server object" do
      node_script = """
      const fs = require('fs');
      const vm = require('vm');
      const code = fs.readFileSync('#{@model_path}', 'utf8');
      const context = {};
      vm.createContext(context);
      vm.runInContext(code, context);

      const simple = context.buildSshCommand({ host: 'example.com', user: 'alice', port: 22 });
      const withProxy = context.buildSshCommand({ host: 'internal.host', user: 'bob', port: 2222, proxy_jump: 'bastion.example.com' });
      const minimal = context.buildSshCommand({ host: '10.0.0.1' });

      console.log(JSON.stringify({ simple, withProxy, minimal }));
      """

      node = System.find_executable("node")

      if node do
        {output, 0} = System.cmd(node, ["-e", node_script])
        {:ok, result} = :json.decode(String.trim(output)) |> then(&{:ok, &1})

        assert result["simple"] == ["ssh", "-l", "alice", "example.com"]

        assert result["withProxy"] == [
                 "ssh",
                 "-J",
                 "bastion.example.com",
                 "-l",
                 "bob",
                 "-p",
                 "2222",
                 "internal.host"
               ]

        assert result["minimal"] == ["ssh", "10.0.0.1"]
      end
    end
  end
end
