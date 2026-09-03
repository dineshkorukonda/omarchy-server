defmodule OmarchyServer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    OmarchyServer.InitSystem.init_cache()

    children = [
      {Registry, keys: :unique, name: OmarchyServer.WorkerRegistry},
      OmarchyServer.ServerSupervisor,
      OmarchyServer.ServerManager
    ]

    opts = [strategy: :one_for_one, name: OmarchyServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
