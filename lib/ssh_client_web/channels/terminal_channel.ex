defmodule SSHClientWeb.TerminalChannel do
  @moduledoc """
  Phoenix Channel bridging terminal I/O between the xterm.js web frontend
  and the underlying `:ssh` pseudo-terminal (`SSHClient.SSH.PTYSession`).

  Events:
  - `"pty:input"`: Keystrokes or binary input from xterm.js → PTYSession
  - `"pty:resize"`: Window dimensions `{cols, rows}` → PTYSession.resize/3
  - Outgoing `"pty:output"`: Raw bytes from remote shell → xterm.js
  """

  use Phoenix.Channel

  alias SSHClient.SSH.PTYSession

  @bracketed_paste_start "\e[200~"
  @bracketed_paste_end "\e[201~"

  @impl true
  def join("terminal:" <> server_id, payload, socket) do
    cols = Map.get(payload, "cols", 80)
    rows = Map.get(payload, "rows", 24)

    socket =
      socket
      |> assign(:server_id, server_id)
      |> assign(:session_pid, nil)
      |> assign(:cols, cols)
      |> assign(:rows, rows)

    {:ok, %{status: "connected", server_id: server_id}, socket}
  end

  def join(_other, _payload, _socket) do
    {:error, %{reason: "unauthorized"}}
  end

  @impl true
  def handle_in("pty:input", %{"data" => data, "bracketed" => true}, socket)
      when is_binary(data) do
    wrapped = @bracketed_paste_start <> data <> @bracketed_paste_end
    handle_in("pty:input", %{"data" => wrapped}, socket)
  end

  def handle_in("pty:paste", %{"data" => data}, socket) when is_binary(data) do
    wrapped = @bracketed_paste_start <> data <> @bracketed_paste_end
    handle_in("pty:input", %{"data" => wrapped}, socket)
  end

  def handle_in("pty:input", %{"data" => data}, socket) when is_binary(data) do
    pid = socket.assigns.session_pid

    if pid && Process.alive?(pid) do
      PTYSession.send_input(pid, data)
    end

    {:reply, :ok, socket}
  end

  def handle_in("pty:resize", %{"cols" => cols, "rows" => rows}, socket)
      when is_integer(cols) and is_integer(rows) do
    pid = socket.assigns.session_pid

    if pid && Process.alive?(pid) do
      PTYSession.resize(pid, cols, rows)
    end

    {:reply, :ok, assign(socket, cols: cols, rows: rows)}
  end

  def handle_in(_event, _payload, socket) do
    {:reply, {:error, %{reason: "unknown_event"}}, socket}
  end

  @doc """
  Wraps multi-line or paste content in ANSI bracketed paste escape sequences.
  """
  def wrap_bracketed_paste(text) when is_binary(text) do
    @bracketed_paste_start <> text <> @bracketed_paste_end
  end
end
