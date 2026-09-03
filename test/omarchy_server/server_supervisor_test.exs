defmodule OmarchyServer.ServerSupervisorTest do
  use ExUnit.Case, async: false

  alias OmarchyServer.Config.Server
  alias OmarchyServer.ServerSupervisor

  @test_server %Server{
    id: "sup-test-worker-1",
    name: "Sup Test Worker 1",
    host: "127.0.0.1",
    port: 22,
    checks: []
  }

  setup do
    if Process.whereis(OmarchyServer.WorkerRegistry) == nil do
      start_supervised!({Registry, keys: :unique, name: OmarchyServer.WorkerRegistry})
    end

    sup = start_supervised!({ServerSupervisor, name: nil})
    %{supervisor: sup}
  end

  test "start_worker, count_workers, which_workers, and stop_worker by pid", %{supervisor: sup} do
    assert ServerSupervisor.count_workers(sup) == 0
    assert ServerSupervisor.which_workers(sup) == []

    mock_runner = fn
      _server, :connect -> {:error, :econnrefused}
      _server, _ -> {:error, :not_connected}
    end

    assert {:ok, pid} =
             ServerSupervisor.start_worker(sup, @test_server,
               runner: mock_runner,
               reconnect_interval: 60_000
             )

    assert is_pid(pid)
    assert ServerSupervisor.count_workers(sup) == 1
    assert length(ServerSupervisor.which_workers(sup)) == 1

    # Stop by pid
    assert :ok = ServerSupervisor.stop_worker(sup, pid)
    assert ServerSupervisor.count_workers(sup) == 0
  end

  test "stop_worker by server_id string and not_found error", %{supervisor: sup} do
    mock_runner = fn
      _server, :connect -> {:error, :econnrefused}
      _server, _ -> {:error, :not_connected}
    end

    assert {:error, :not_found} = ServerSupervisor.stop_worker(sup, "non-existent-server")

    assert {:ok, _pid} =
             ServerSupervisor.start_worker(sup, @test_server,
               runner: mock_runner,
               reconnect_interval: 60_000
             )

    assert :ok = ServerSupervisor.stop_worker(sup, @test_server.id)
    assert ServerSupervisor.count_workers(sup) == 0
  end
end
