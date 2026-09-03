defmodule OmarchyServer.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    OmarchyServer.InitSystem.init_cache()

    config_path =
      if Code.ensure_loaded?(Mix) and Mix.env() == :test do
        nil
      else
        OmarchyServer.Config.default_config_path()
      end

    manager_child =
      if config_path do
        {OmarchyServer.ServerManager, config_path: config_path}
      else
        OmarchyServer.ServerManager
      end

    children = [
      {Registry, keys: :unique, name: OmarchyServer.WorkerRegistry},
      OmarchyServer.ServerSupervisor,
      manager_child,
      OmarchyServer.TerminalSupervisor,
      OmarchyServer.SocketAPI
    ]

    opts = [strategy: :one_for_one, name: OmarchyServer.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
