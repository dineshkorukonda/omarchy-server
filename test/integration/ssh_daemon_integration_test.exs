defmodule SSHClient.Integration.SSHDaemonIntegrationTest do
  use ExUnit.Case, async: false

  alias SSHClient.Config.Server
  alias SSHClient.InitSystem
  alias SSHClient.Metrics
  alias SSHClient.ServerWorker
  alias SSHClient.SSH

  @moduletag :integration

  @key_path Path.expand("test/fixtures/docker/ssh-target/id_ed25519")
  @ssh_server %Server{
    id: "docker-ssh-target",
    name: "Docker SSH Target",
    host: "127.0.0.1",
    port: 2222,
    user: "testuser",
    checks: []
  }

  setup_all do
    # Verify ssh-target container is reachable before running suite
    opts = [
      user: "testuser",
      user_dir: Path.dirname(@key_path),
      timeout: 3000
    ]

    case SSH.run(@ssh_server, "echo ready", opts) do
      {:ok, out, 0} ->
        if String.contains?(out, "ready") do
          :ok
        else
          {:error, "Unexpected response from container: #{inspect(out)}"}
        end

      other ->
        {:error, "Integration container not reachable on 127.0.0.1:2222: #{inspect(other)}"}
    end
  end

  test "SSH executes remote commands directly on container" do
    opts = [
      user: "testuser",
      user_dir: Path.dirname(@key_path),
      timeout: 5000
    ]

    assert {:ok, output, 0} = SSH.run(@ssh_server, "whoami && uname -s", opts)
    assert output =~ "testuser"
    assert output =~ "Linux"
  end

  test "InitSystem detects container init system via SSH" do
    opts = [
      user: "testuser",
      user_dir: Path.dirname(@key_path),
      timeout: 5000
    ]

    runner = fn cmd ->
      case SSH.run(@ssh_server, cmd, opts) do
        {:ok, out, _code} -> {:ok, out}
        {:error, reason} -> {:error, reason}
      end
    end

    assert {:ok, init_type} = InitSystem.detect(runner)
    assert init_type in [:openrc, :unsupported, :sysvinit, :systemd]
  end

  test "Metrics collects real CPU, memory, and disk from container" do
    opts = [
      user: "testuser",
      user_dir: Path.dirname(@key_path),
      timeout: 5000
    ]

    runner = fn cmd ->
      case SSH.run(@ssh_server, cmd, opts) do
        {:ok, out, _code} -> {:ok, out}
        {:error, reason} -> {:error, reason}
      end
    end

    assert {:ok, metrics} = Metrics.collect(runner)
    assert is_map(metrics.cpu)
    assert is_map(metrics.memory)
    assert is_map(metrics.disk)
    assert metrics.memory.total_mb > 0
  end

  test "ServerWorker connects, polls, and retrieves real state end to end" do
    if Process.whereis(SSHClient.WorkerRegistry) == nil do
      start_supervised!({Registry, keys: :unique, name: SSHClient.WorkerRegistry})
    end

    key_dir = Path.dirname(@key_path)

    worker_runner = fn
      server, :connect ->
        SSH.connect(server, user_dir: key_dir, timeout: 5000)

      _server, {:exec, conn, cmd} ->
        SSH.exec(conn, cmd, timeout: 5000)

      _server, {:poll, conn, checks} ->
        with {:ok, metrics} <- Metrics.collect(conn),
             {:ok, checks_map} <- SSHClient.ServiceChecks.check_all(checks, conn) do
          {:ok, %{metrics: metrics, checks: checks_map}}
        end

      _server, {:close, conn} ->
        SSH.close(conn)
    end

    {:ok, worker} =
      ServerWorker.start_link(@ssh_server,
        runner: worker_runner,
        name: nil,
        poll_interval: 10_000
      )

    Process.sleep(200)

    assert ServerWorker.get_status(worker) == :polling
    state = ServerWorker.get_state(worker)
    assert state.status == :polling
    assert is_map(state.metrics)
    assert is_map(state.metrics.memory)
    assert state.metrics.memory.total_mb > 0
  end
end
