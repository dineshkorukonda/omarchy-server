defmodule OmarchyServer.ServerManager do
  @moduledoc """
  Coordinates ServerWorkers under ServerSupervisor, reconciling changes from servers.yaml.
  """

  use GenServer

  alias OmarchyServer.Config
  alias OmarchyServer.Config.Server
  alias OmarchyServer.ServerSupervisor
  alias OmarchyServer.ServerWorker

  @name __MODULE__

  defstruct [
    :config_path,
    :supervisor,
    :runner,
    workers: %{},
    poll_interval: 5000
  ]

  @doc """
  Starts the ServerManager coordinator process.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Synchronizes running workers with a Config struct or list of Server structs.
  Starts workers for new servers and stops workers for removed servers.
  """
  def sync_config(config_or_servers)
      when is_list(config_or_servers) or is_struct(config_or_servers, Config) do
    sync_config(@name, config_or_servers, [])
  end

  def sync_config(manager, config_or_servers)
      when (is_pid(manager) or is_atom(manager)) and
             (is_list(config_or_servers) or is_struct(config_or_servers, Config)) do
    sync_config(manager, config_or_servers, [])
  end

  def sync_config(config_or_servers, opts)
      when is_list(opts) and
             (is_list(config_or_servers) or is_struct(config_or_servers, Config)) do
    sync_config(@name, config_or_servers, opts)
  end

  def sync_config(manager, config_or_servers, opts) do
    GenServer.call(manager, {:sync_config, config_or_servers, opts})
  end

  @doc """
  Loads config from a YAML file and synchronizes running workers.
  """
  def sync_file do
    sync_file(@name, nil, [])
  end

  def sync_file(path) when is_binary(path) do
    sync_file(@name, path, [])
  end

  def sync_file(manager, path)
      when (is_pid(manager) or is_atom(manager)) and (is_binary(path) or is_nil(path)) do
    sync_file(manager, path, [])
  end

  def sync_file(path, opts) when is_binary(path) and is_list(opts) do
    sync_file(@name, path, opts)
  end

  def sync_file(manager, path, opts) do
    GenServer.call(manager, {:sync_file, path, opts})
  end

  @doc """
  Lists the current state snapshot of all running servers.
  """
  def list_servers(manager \\ @name) do
    GenServer.call(manager, :list_servers)
  end

  @doc """
  Returns the snapshot state for a specific server id.
  """
  def get_server(manager \\ @name, server_id) do
    GenServer.call(manager, {:get_server, server_id})
  end

  @doc """
  Returns map of active workers %{server_id => pid}.
  """
  def get_workers(manager \\ @name) do
    GenServer.call(manager, :get_workers)
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    config_path = Keyword.get(opts, :config_path)
    supervisor = Keyword.get(opts, :supervisor, ServerSupervisor)
    runner = Keyword.get(opts, :runner)
    poll_interval = Keyword.get(opts, :poll_interval, 5000)

    state = %__MODULE__{
      config_path: config_path,
      supervisor: supervisor,
      runner: runner,
      poll_interval: poll_interval,
      workers: %{}
    }

    if config_path && File.exists?(config_path) do
      {:ok, state, {:continue, {:sync_file, config_path}}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue({:sync_file, path}, state) do
    case do_sync_file(state, path, []) do
      {:ok, new_state, _result} -> {:noreply, new_state}
      {:error, _reason} -> {:noreply, state}
    end
  end

  @impl true
  def handle_call({:sync_config, config_or_servers, opts}, _from, state) do
    case do_sync_config(state, config_or_servers, opts) do
      {:ok, new_state, result} -> {:reply, {:ok, result}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call({:sync_file, path, opts}, _from, state) do
    case do_sync_file(state, path, opts) do
      {:ok, new_state, result} -> {:reply, {:ok, result}, new_state}
      {:error, reason} -> {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:list_servers, _from, state) do
    servers =
      state.workers
      |> Enum.map(fn {_id, pid} ->
        try do
          ServerWorker.get_state(pid)
        rescue
          _ -> nil
        catch
          :exit, _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)

    {:reply, servers, state}
  end

  @impl true
  def handle_call({:get_server, server_id}, _from, state) do
    case Map.get(state.workers, server_id) do
      pid when is_pid(pid) ->
        try do
          {:reply, {:ok, ServerWorker.get_state(pid)}, state}
        rescue
          _ -> {:reply, {:error, :worker_unavailable}, state}
        catch
          :exit, _ -> {:reply, {:error, :worker_unavailable}, state}
        end

      nil ->
        {:reply, {:error, :not_found}, state}
    end
  end

  @impl true
  def handle_call(:get_workers, _from, state) do
    {:reply, state.workers, state}
  end

  # Internal Logic

  defp do_sync_file(state, path, opts) do
    target_path = path || state.config_path || "servers.yaml"

    case Config.load_file(target_path) do
      {:ok, config} ->
        do_sync_config(%{state | config_path: target_path}, config, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_sync_config(state, %Config{servers: servers}, opts) do
    do_sync_servers(state, servers, opts)
  end

  defp do_sync_config(state, servers, opts) when is_list(servers) do
    do_sync_servers(state, servers, opts)
  end

  defp do_sync_config(_state, _invalid, _opts) do
    {:error, "invalid configuration target: expected %OmarchyServer.Config{} or list of servers"}
  end

  defp do_sync_servers(state, new_servers, opts) do
    target_servers = Map.new(new_servers, fn %Server{id: id} = s -> {id, s} end)
    current_ids = Map.keys(state.workers)
    target_ids = Map.keys(target_servers)

    ids_to_add = target_ids -- current_ids
    ids_to_remove = current_ids -- target_ids

    # 1. Stop removed servers
    updated_workers =
      Enum.reduce(ids_to_remove, state.workers, fn id, acc ->
        pid = Map.get(acc, id)
        ServerSupervisor.stop_worker(state.supervisor, pid)
        Map.delete(acc, id)
      end)

    # 2. Start new servers
    runner = Keyword.get(opts, :runner, state.runner)
    poll_interval = Keyword.get(opts, :poll_interval, state.poll_interval)

    worker_opts = [
      poll_interval: poll_interval
    ]

    worker_opts =
      if runner do
        Keyword.put(worker_opts, :runner, runner)
      else
        worker_opts
      end

    {final_workers, added_ids} =
      Enum.reduce(ids_to_add, {updated_workers, []}, fn id, {acc, added} ->
        server = Map.fetch!(target_servers, id)

        case ServerSupervisor.start_worker(state.supervisor, server, worker_opts) do
          {:ok, pid} ->
            {Map.put(acc, id, pid), [id | added]}

          {:error, {:already_started, pid}} ->
            {Map.put(acc, id, pid), added}

          _other ->
            {acc, added}
        end
      end)

    result = %{
      added: Enum.reverse(added_ids),
      removed: ids_to_remove,
      total_active: map_size(final_workers)
    }

    {:ok, %{state | workers: final_workers}, result}
  end
end
