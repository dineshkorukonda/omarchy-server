defmodule SSHClient.ServerSupervisor do
  @moduledoc """
  DynamicSupervisor managing individual ServerWorker processes.
  """

  use DynamicSupervisor

  alias SSHClient.Config.Server
  alias SSHClient.ServerWorker

  @name __MODULE__

  def start_link(init_arg \\ []) do
    name = Keyword.get(init_arg, :name, @name)
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: name)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a ServerWorker under the DynamicSupervisor.
  """
  def start_worker(supervisor \\ @name, %Server{} = server, opts \\ []) do
    spec = {ServerWorker, {server, opts}}
    DynamicSupervisor.start_child(supervisor, spec)
  end

  @doc """
  Stops a ServerWorker by its pid or server ID.
  """
  def stop_worker(supervisor \\ @name, target)

  def stop_worker(supervisor, pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(supervisor, pid)
  end

  def stop_worker(supervisor, server_id) when is_binary(server_id) do
    case ServerWorker.whereis(server_id) do
      pid when is_pid(pid) ->
        DynamicSupervisor.terminate_child(supervisor, pid)

      nil ->
        {:error, :not_found}
    end
  end

  @doc """
  Lists all active children.
  """
  def which_workers(supervisor \\ @name) do
    DynamicSupervisor.which_children(supervisor)
  end

  @doc """
  Returns the count of active workers.
  """
  def count_workers(supervisor \\ @name) do
    DynamicSupervisor.count_children(supervisor).active
  end
end
