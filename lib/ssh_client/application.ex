defmodule SSHClient.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    SSHClient.InitSystem.init_cache()

    config_path =
      if Code.ensure_loaded?(Mix) and Mix.env() == :test do
        nil
      else
        SSHClient.Config.default_config_path()
      end

    manager_child =
      if config_path do
        {SSHClient.ServerManager, config_path: config_path}
      else
        SSHClient.ServerManager
      end

    children = [
      {Registry, keys: :unique, name: SSHClient.WorkerRegistry},
      SSHClient.ServerSupervisor,
      manager_child,
      SSHClient.TerminalSupervisor,
      SSHClient.SocketAPI
    ]

    opts = [strategy: :one_for_one, name: SSHClient.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
