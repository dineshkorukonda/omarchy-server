defmodule OmarchyServer.ServerWorker do
  @moduledoc """
  GenServer maintaining state machine and monitoring loop for an individual server.
  States: :connecting -> :polling -> :degraded -> :reconnecting.
  """

  use GenServer, restart: :permanent

  alias OmarchyServer.Config.Server
  alias OmarchyServer.InitSystem
  alias OmarchyServer.SSH

  @type status :: :connecting | :polling | :degraded | :reconnecting

  defstruct [
    :server,
    :connection,
    :init_system,
    :runner,
    status: :connecting,
    metrics: %{},
    checks: %{},
    consecutive_failures: 0,
    poll_interval: 5000,
    reconnect_interval: 2000,
    last_error: nil,
    updated_at: nil
  ]

  @doc """
  Starts a ServerWorker for a given server configuration.
  """
  def start_link(server_or_opts, opts \\ [])

  def start_link({%Server{} = server, opts}, _default_opts) do
    start_link(server, opts)
  end

  def start_link(%Server{} = server, opts) do
    gen_opts =
      case Keyword.get(opts, :name, :default) do
        :default ->
          if Process.whereis(OmarchyServer.WorkerRegistry) do
            [name: via_registry(server.id)]
          else
            []
          end

        nil ->
          []

        name ->
          [name: name]
      end

    GenServer.start_link(__MODULE__, {server, opts}, gen_opts)
  end

  def start_link(opts_list, opts) when is_list(opts_list) do
    server = Keyword.fetch!(opts_list, :server)
    start_link(server, opts)
  end

  @doc """
  Returns the full snapshot state of a server worker.
  """
  def get_state(worker) do
    GenServer.call(resolve_worker(worker), :get_state)
  end

  @doc """
  Returns the current status of a server worker (:connecting | :polling | :degraded | :reconnecting).
  """
  def get_status(worker) do
    GenServer.call(resolve_worker(worker), :get_status)
  end

  @doc """
  Manually triggers a poll on the server worker.
  """
  def poll_now(worker) do
    GenServer.call(resolve_worker(worker), :poll_now)
  end

  @doc """
  Forces a reconnection attempt.
  """
  def reconnect(worker) do
    GenServer.call(resolve_worker(worker), :reconnect)
  end

  @doc """
  Looks up the worker pid in the registry for a server id.
  """
  def whereis(server_id) when is_binary(server_id) do
    case Registry.lookup(OmarchyServer.WorkerRegistry, server_id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  rescue
    _ -> nil
  end

  def via_registry(server_id) do
    {:via, Registry, {OmarchyServer.WorkerRegistry, server_id}}
  end

  # Server Callbacks

  @impl true
  def init({%Server{} = server, opts}) do
    runner = Keyword.get(opts, :runner, &default_runner/2)
    poll_interval = Keyword.get(opts, :poll_interval, 5000)
    reconnect_interval = Keyword.get(opts, :reconnect_interval, 2000)

    state = %__MODULE__{
      server: server,
      runner: runner,
      status: :connecting,
      poll_interval: poll_interval,
      reconnect_interval: reconnect_interval,
      updated_at: DateTime.utc_now()
    }

    auto_connect = Keyword.get(opts, :auto_connect, true)

    if auto_connect do
      {:ok, state, {:continue, :connect}}
    else
      {:ok, state}
    end
  end

  @impl true
  def handle_continue(:connect, state) do
    {:noreply, do_connect(state)}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    snapshot = %{
      id: state.server.id,
      name: state.server.name,
      host: state.server.host,
      status: state.status,
      metrics: state.metrics,
      checks: state.checks,
      init_system: state.init_system,
      last_error: state.last_error,
      updated_at: state.updated_at
    }

    {:reply, snapshot, state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    {:reply, state.status, state}
  end

  @impl true
  def handle_call(:poll_now, _from, state) do
    new_state = do_poll(state)
    {:reply, {:ok, new_state.status}, new_state}
  end

  @impl true
  def handle_call(:reconnect, _from, state) do
    close_connection(state)
    new_state = %{state | status: :connecting, connection: nil}
    {:reply, :ok, do_connect(new_state)}
  end

  @impl true
  def handle_info(:connect, state) do
    {:noreply, do_connect(state)}
  end

  @impl true
  def handle_info(:poll, state) do
    new_state = do_poll(state)

    if new_state.status in [:polling, :degraded] do
      schedule_poll(new_state.poll_interval)
    end

    {:noreply, new_state}
  end

  @impl true
  def handle_info(:reconnect_timer, state) do
    new_state = %{state | status: :connecting}
    {:noreply, do_connect(new_state)}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    close_connection(state)
    :ok
  end

  # Internal Logic

  defp do_connect(state) do
    case state.runner.(state.server, :connect) do
      {:ok, conn} ->
        init_system = probe_init_system(state.server, conn, state.runner)

        new_state = %{
          state
          | connection: conn,
            init_system: init_system,
            status: :polling,
            consecutive_failures: 0,
            last_error: nil,
            updated_at: DateTime.utc_now()
        }

        schedule_poll(0)
        new_state

      {:error, reason} ->
        schedule_reconnect(state.reconnect_interval)

        %{
          state
          | status: :reconnecting,
            connection: nil,
            last_error: reason,
            updated_at: DateTime.utc_now()
        }
    end
  end

  defp do_poll(%{status: :reconnecting} = state), do: state

  defp do_poll(state) do
    case state.runner.(state.server, {:poll, state.connection, state.server.checks}) do
      {:ok, %{metrics: metrics, checks: checks, degraded: degraded}} ->
        new_status = if degraded, do: :degraded, else: :polling

        %{
          state
          | status: new_status,
            metrics: metrics,
            checks: checks,
            consecutive_failures: 0,
            last_error: nil,
            updated_at: DateTime.utc_now()
        }

      {:ok, %{metrics: metrics, checks: checks}} ->
        %{
          state
          | status: :polling,
            metrics: metrics,
            checks: checks,
            consecutive_failures: 0,
            last_error: nil,
            updated_at: DateTime.utc_now()
        }

      {:degraded, reason, partial_data} ->
        %{
          state
          | status: :degraded,
            metrics: Map.get(partial_data, :metrics, state.metrics),
            checks: Map.get(partial_data, :checks, state.checks),
            last_error: reason,
            updated_at: DateTime.utc_now()
        }

      {:error, :connection_lost} ->
        transition_to_reconnecting(state, :connection_lost)

      {:error, {:connection_failed, _} = reason} ->
        transition_to_reconnecting(state, reason)

      {:error, other_error} ->
        failures = state.consecutive_failures + 1

        if failures >= 3 do
          transition_to_reconnecting(state, other_error)
        else
          %{
            state
            | status: :degraded,
              consecutive_failures: failures,
              last_error: other_error,
              updated_at: DateTime.utc_now()
          }
        end
    end
  end

  defp transition_to_reconnecting(state, reason) do
    close_connection(state)
    schedule_reconnect(state.reconnect_interval)

    %{
      state
      | status: :reconnecting,
        connection: nil,
        last_error: reason,
        updated_at: DateTime.utc_now()
    }
  end

  defp probe_init_system(server, conn, runner) do
    probe_fn = fn cmd -> runner.(server, {:exec, conn, cmd}) end

    case InitSystem.detect(probe_fn, server.id) do
      {:ok, init_sys} -> init_sys
      _ -> :unsupported
    end
  end

  defp close_connection(%{connection: conn, runner: runner, server: server})
       when not is_nil(conn) do
    try do
      runner.(server, {:close, conn})
    catch
      _, _ -> :ok
    end
  end

  defp close_connection(_), do: :ok

  defp schedule_poll(delay_ms) do
    Process.send_after(self(), :poll, delay_ms)
  end

  defp schedule_reconnect(delay_ms) do
    Process.send_after(self(), :reconnect_timer, delay_ms)
  end

  defp resolve_worker(pid) when is_pid(pid), do: pid

  defp resolve_worker(server_id) when is_binary(server_id) do
    case whereis(server_id) do
      pid when is_pid(pid) -> pid
      nil -> via_registry(server_id)
    end
  end

  defp resolve_worker(other), do: other

  defp default_runner(server, :connect) do
    SSH.connect(server)
  end

  defp default_runner(_server, {:close, conn}) do
    SSH.close(conn)
  end

  defp default_runner(_server, {:exec, conn, cmd}) do
    SSH.exec(conn, cmd)
  end

  defp default_runner(_server, {:poll, conn, _checks}) do
    case SSH.exec(conn, "uptime") do
      {:ok, output, 0} ->
        {:ok, %{metrics: %{uptime: String.trim(output)}, checks: %{}}}

      {:ok, _output, code} ->
        {:degraded, {:nonzero_exit, code}, %{}}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
