defmodule SSHClientWeb.TerminalChannel do
  @moduledoc """
  Phoenix Channel bridging terminal I/O between the xterm.js web frontend
  and the underlying `:ssh` pseudo-terminal (`SSHClient.SSH.PTYSession`).

  Events:
  - `"pty:input"`: Keystrokes or binary input from xterm.js → PTYSession
  - `"pty:resize"`: Window dimensions `{cols, rows}` → PTYSession.resize/3
  - Outgoing `"pty:output"`: Raw bytes from remote shell → xterm.js
  """

  alias SSHClient.SSH.PTYSession

  defstruct [
    :session_pid,
    :server_id,
    cols: 80,
    rows: 24
  ]

  @doc """
  Handles client join request to topic `"terminal:" <> server_id`.
  """
  def join(topic, payload, socket_state \\ %{})

  def join("terminal:" <> server_id, payload, socket_state) do
    cols = Map.get(payload, "cols", 80)
    rows = Map.get(payload, "rows", 24)

    state = %__MODULE__{
      server_id: server_id,
      cols: cols,
      rows: rows
    }

    {:ok, %{status: "connected", server_id: server_id}, Map.merge(socket_state, %{terminal: state})}
  end

  def join(_other, _payload, _socket_state) do
    {:error, %{reason: "unauthorized"}}
  end

  @doc """
  Handles client events from xterm.js.
  """
  def handle_in("pty:input", %{"data" => data}, socket_state) when is_binary(data) do
    terminal = Map.get(socket_state, :terminal)

    if terminal && terminal.session_pid && Process.alive?(terminal.session_pid) do
      PTYSession.send_input(terminal.session_pid, data)
    end

    {:reply, :ok, socket_state}
  end

  def handle_in("pty:resize", %{"cols" => cols, "rows" => rows}, socket_state)
      when is_integer(cols) and is_integer(rows) do
    terminal = Map.get(socket_state, :terminal)

    if terminal && terminal.session_pid && Process.alive?(terminal.session_pid) do
      PTYSession.resize(terminal.session_pid, cols, rows)
    end

    new_terminal =
      if terminal do
        %{terminal | cols: cols, rows: rows}
      else
        %__MODULE__{cols: cols, rows: rows}
      end

    {:reply, :ok, Map.put(socket_state, :terminal, new_terminal)}
  end

  def handle_in(_event, _payload, socket_state) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket_state}
  end

  @doc """
  Handles output messages from PTYSession and formats them for the channel push.
  """
  def handle_pty_data(data) when is_binary(data) do
    {:push, "pty:output", %{data: data}}
  end

  def handle_pty_eof do
    {:push, "pty:closed", %{reason: "eof"}}
  end
end
