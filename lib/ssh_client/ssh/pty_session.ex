defmodule SSHClient.SSH.PTYSession do
  @moduledoc """
  Manages an interactive pseudo-terminal (PTY) SSH session, bridging raw byte
  streams between an SSH channel and a client process.
  """

  use GenServer, restart: :temporary

  alias SSHClient.Config.Server
  alias SSHClient.SSH
  alias SSHClient.Terminal.Buffer

  defstruct [
    :server,
    :connection,
    :channel_id,
    :client_pid,
    :client_ref,
    :buffer,
    cols: 80,
    rows: 24,
    term: "xterm-256color"
  ]

  @doc """
  Starts a PTY session process for a target server.
  Options:
    - `:client_pid` (required): Process to receive output bytes as `{:pty_data, session_id, binary}`
    - `:cols`: Initial terminal columns (default: 80)
    - `:rows`: Initial terminal rows (default: 24)
    - `:term`: Terminal type (default: "xterm-256color")
  """
  def start_link({%Server{} = server, opts}) when is_list(opts) do
    GenServer.start_link(__MODULE__, {server, opts})
  end

  def start_link(server) do
    GenServer.start_link(__MODULE__, {server, []})
  end

  def start_link(%Server{} = server, opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, {server, opts})
  end

  @doc """
  Sends raw input bytes into the PTY session.
  """
  def send_input(session, data) when is_binary(data) do
    GenServer.cast(session, {:send_input, data})
  end

  @doc """
  Resizes the PTY window dimensions.
  """
  def resize(session, cols, rows) when is_integer(cols) and is_integer(rows) do
    GenServer.cast(session, {:resize, cols, rows})
  end

  @doc """
  Returns a snapshot map of the terminal screen buffer.
  """
  def get_buffer(session) do
    GenServer.call(session, :get_buffer)
  end

  @doc """
  Terminates the PTY session and closes the channel.
  """
  def close(session) do
    GenServer.stop(session, :normal)
  end

  # GenServer Callbacks

  @impl true
  def init({%Server{} = server, opts}) do
    client_pid = Keyword.fetch!(opts, :client_pid)
    client_ref = Process.monitor(client_pid)
    cols = Keyword.get(opts, :cols, 80)
    rows = Keyword.get(opts, :rows, 24)
    term = Keyword.get(opts, :term, "xterm-256color")
    buffer = Buffer.new(cols, rows)

    state = %__MODULE__{
      server: server,
      client_pid: client_pid,
      client_ref: client_ref,
      cols: cols,
      rows: rows,
      term: term,
      buffer: buffer
    }

    {:ok, state, {:continue, :connect}}
  end

  @impl true
  def handle_continue(:connect, state) do
    case SSH.connect(state.server) do
      {:ok, conn} ->
        case SSH.open_pty(conn, cols: state.cols, rows: state.rows, term: state.term) do
          {:ok, channel_id} ->
            notify_client(state, {:pty_connected, self()})
            {:noreply, %{state | connection: conn, channel_id: channel_id}}

          {:error, reason} ->
            notify_client(state, {:pty_error, reason})
            {:stop, {:pty_failed, reason}, state}
        end

      {:error, reason} ->
        notify_client(state, {:pty_error, reason})
        {:stop, {:connect_failed, reason}, state}
    end
  end

  @impl true
  def handle_call(:get_buffer, _from, state) do
    snapshot = if state.buffer, do: Buffer.to_snapshot(state.buffer), else: %{}
    {:reply, snapshot, state}
  end

  @impl true
  def handle_cast({:send_input, data}, state) do
    if state.connection && state.channel_id do
      SSH.send_pty_data(state.connection, state.channel_id, data)
    end

    {:noreply, state}
  end

  @impl true
  def handle_cast({:resize, cols, rows}, state) do
    if state.connection && state.channel_id do
      SSH.resize_pty(state.connection, state.channel_id, cols, rows)
    end

    new_buf = if state.buffer, do: Buffer.resize(state.buffer, cols, rows), else: nil
    {:noreply, %{state | cols: cols, rows: rows, buffer: new_buf}}
  end

  # Incoming messages from OTP SSH channel
  @impl true
  def handle_info({:ssh_cm, _conn_ref, {:data, channel_id, 0, data}}, state) do
    new_state =
      if channel_id == state.channel_id do
        new_buf = if state.buffer, do: Buffer.feed(state.buffer, data), else: nil
        notify_client(state, {:pty_data, self(), data})
        %{state | buffer: new_buf}
      else
        state
      end

    {:noreply, new_state}
  end

  @impl true
  def handle_info({:ssh_cm, _conn_ref, {:eof, channel_id}}, state) do
    if channel_id == state.channel_id do
      notify_client(state, {:pty_eof, self()})
    end

    {:noreply, state}
  end

  @impl true
  def handle_info({:ssh_cm, _conn_ref, {:exit_status, channel_id, exit_code}}, state) do
    if channel_id == state.channel_id do
      notify_client(state, {:pty_exit, self(), exit_code})
    end

    {:stop, :normal, state}
  end

  @impl true
  def handle_info({:ssh_cm, _conn_ref, {:closed, channel_id}}, state) do
    if channel_id == state.channel_id do
      notify_client(state, {:pty_closed, self()})
    end

    {:stop, :normal, state}
  end

  # Monitor client process — if client exits, terminate session
  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, %{client_ref: ref} = state) do
    {:stop, :normal, state}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  @impl true
  def terminate(_reason, state) do
    if state.connection && state.channel_id do
      SSH.close_pty(state.connection, state.channel_id)
      SSH.close(state.connection)
    end

    :ok
  end

  defp notify_client(%{client_pid: pid}, msg) when is_pid(pid) do
    send(pid, msg)
  end

  defp notify_client(_state, _msg), do: :ok
end
