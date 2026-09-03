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
      end
    end
  end
end
