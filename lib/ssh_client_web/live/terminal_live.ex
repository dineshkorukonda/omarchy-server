defmodule SSHClientWeb.TerminalLive do
  @moduledoc """
  Phoenix LiveView hosting the interactive xterm.js embedded terminal.
  Supervises a PTYSession process, bridges bidirectional I/O, handles
  window resize, and outputs real-time diagnostics.
  """

  use Phoenix.LiveView, layout: {SSHClientWeb.Layouts, :app}

  alias SSHClient.ActivityLog
  alias SSHClient.Config
  alias SSHClient.Config.Server
  alias SSHClient.ServerManager
  alias SSHClient.SSH.PTYSession
  alias SSHClient.TerminalSupervisor

  @impl true
  def mount(%{"id" => server_id}, _session, socket) do
    server = resolve_server_struct(server_id)

    socket =
      socket
      |> assign(:page_title, "Terminal — #{server_id}")
      |> assign(:server_id, server_id)
      |> assign(:server, server)
      |> assign(:session_pid, nil)
      |> assign(:connected, false)
      |> assign(:error, nil)
      |> assign(:cols, 80)
      |> assign(:rows, 24)

    {:ok, socket}
  end

  @impl true
  def handle_event("terminal_ready", _params, socket) do
    socket = start_terminal_session(socket)
    {:noreply, socket}
  end

  def handle_event("terminal_data", %{"data" => data}, socket) when is_binary(data) do
    pid = socket.assigns.session_pid

    if pid && Process.alive?(pid) do
      PTYSession.send_input(pid, data)
    end

    {:noreply, socket}
  end

  def handle_event("resize", %{"cols" => cols, "rows" => rows}, socket)
      when is_integer(cols) and is_integer(rows) do
    pid = socket.assigns.session_pid

    if pid && Process.alive?(pid) do
      PTYSession.resize(pid, cols, rows)
    end

    {:noreply, assign(socket, cols: cols, rows: rows)}
  end

  def handle_event("reconnect", _params, socket) do
    if pid = socket.assigns.session_pid do
      if Process.alive?(pid), do: PTYSession.close(pid)
    end

    socket =
      socket
      |> assign(session_pid: nil, connected: false, error: nil)
      |> push_event("terminal_output", %{
        data: "\r\n\x1b[1;34m[ssh-client]\x1b[0m \x1b[2mReconnecting to #{socket.assigns.server_id}...\x1b[0m\r\n"
      })
      |> start_terminal_session()

    {:noreply, socket}
  end

  # ---------------------------------------------------------------------------
  # Messages from PTYSession
  # ---------------------------------------------------------------------------

  @impl true
  def handle_info({:pty_connected, pid}, socket) do
    ActivityLog.info(socket.assigns.server_id, "Interactive terminal shell ready")

    socket =
      socket
      |> assign(connected: true, session_pid: pid, error: nil)
      |> push_event("terminal_output", %{
        data: "\x1b[1;32m\u2713 Connected to #{socket.assigns.server_id}\x1b[0m\r\n\r\n"
      })

    {:noreply, socket}
  end

  @impl true
  def handle_info({:pty_data, _pid, data}, socket) do
    {:noreply, push_event(socket, "terminal_output", %{data: data})}
  end

  @impl true
  def handle_info({:pty_error, reason}, socket) do
    err_str = format_error_reason(reason)
    ActivityLog.error(socket.assigns.server_id, "PTY Error: #{err_str}", reason)

    ansi_msg =
      "\r\n\x1b[1;31m[SSH Connection Error]\x1b[0m #{err_str}\r\n" <>
        "\x1b[2mCheck server host, port, credentials, or see the \x1b[1;34mLogs\x1b[0m\x1b[2m tab for full details.\x1b[0m\r\n"

    socket =
      socket
      |> assign(connected: false, error: err_str)
      |> push_event("terminal_output", %{data: ansi_msg})

    {:noreply, socket}
  end

  @impl true
  def handle_info({:pty_eof, _pid}, socket) do
    {:noreply,
     push_event(socket, "terminal_output", %{
       data: "\r\n\x1b[2m[Remote shell sent EOF]\x1b[0m\r\n"
     })}
  end

  @impl true
  def handle_info({:pty_exit, _pid, exit_code}, socket) do
    {:noreply,
     socket
     |> assign(connected: false)
     |> push_event("terminal_output", %{
       data: "\r\n\x1b[2m[Process exited with status #{exit_code}]\x1b[0m\r\n"
     })}
  end

  @impl true
  def handle_info({:pty_closed, _pid}, socket) do
    {:noreply,
     socket
     |> assign(connected: false)
     |> push_event("terminal_output", %{
       data: "\r\n\x1b[2m[Connection closed by remote host]\x1b[0m\r\n"
     })}
  end

  @impl true
  def handle_info(_msg, socket) do
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, socket) do
    if pid = socket.assigns[:session_pid] do
      if Process.alive?(pid) do
        PTYSession.close(pid)
      end
    end

    :ok
  end

  # ---------------------------------------------------------------------------
  # Render
  # ---------------------------------------------------------------------------

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-[#050505]">
      <!-- Terminal topbar -->
      <div class="h-11 flex items-center justify-between px-4 bg-[#0a0a0a] border-b border-[#1f1f1f] shrink-0">
        <div class="flex items-center gap-3">
          <a
            href="/"
            class="text-zinc-500 hover:text-zinc-300 text-xs font-mono transition-colors inline-flex items-center gap-1 px-2 py-1 rounded bg-[#111] hover:bg-[#1a1a1a] border border-[#1f1f1f]"
          >
            &larr; Hosts
          </a>
          <span class="text-zinc-700">|</span>
          <span class="text-zinc-200 text-xs font-mono font-medium"><%= @server_id %></span>
          <%= if @server do %>
            <span class="text-zinc-600 text-[11px] font-mono"><%= @server.user %>@<%= @server.host %>:<%= @server.port || 22 %></span>
          <% end %>
        </div>

        <div class="flex items-center gap-3">
          <!-- Connection badge -->
          <span class={["inline-flex items-center gap-1.5 text-[11px] font-mono px-2.5 py-0.5 rounded-full border",
            if(@connected, do: "bg-emerald-500/10 text-emerald-400 border-emerald-500/20", else: if(@error, do: "bg-red-500/10 text-red-400 border-red-500/20", else: "bg-blue-500/10 text-blue-400 border-blue-500/20"))]}>
            <span class={["w-1.5 h-1.5 rounded-full",
              if(@connected, do: "bg-emerald-400 animate-pulse", else: if(@error, do: "bg-red-400", else: "bg-blue-400 animate-ping"))]}></span>
            <%= if @connected, do: "connected", else: if(@error, do: "disconnected", else: "connecting...") %>
          </span>

          <span class="text-zinc-600 text-[11px] font-mono"><%= @cols %>x<%= @rows %></span>

          <!-- Action buttons -->
          <button
            phx-click="reconnect"
            class="h-7 px-2.5 bg-[#111] hover:bg-[#1a1a1a] border border-[#1f1f1f] hover:border-zinc-600 text-zinc-300 text-xs rounded-lg transition-colors font-mono"
          >
            Reconnect
          </button>
          <a
            href="/logs"
            class="h-7 px-2.5 bg-[#111] hover:bg-[#1a1a1a] border border-[#1f1f1f] hover:border-zinc-600 text-zinc-400 hover:text-zinc-200 text-xs rounded-lg transition-colors font-mono inline-flex items-center"
          >
            Logs
          </a>
        </div>
      </div>

      <!-- xterm.js container -->
      <div
        id="xterm-container"
        phx-hook="TerminalHook"
        phx-update="ignore"
        class="flex-1 w-full overflow-hidden p-2"
        data-server-id={@server_id}
        data-cols={@cols}
        data-rows={@rows}
      ></div>
    </div>
    """
  end

  # ---------------------------------------------------------------------------
  # Helpers
  # ---------------------------------------------------------------------------

  defp start_terminal_session(socket) do
    case socket.assigns.server do
      %Server{} = server ->
        opts = [
          client_pid: self(),
          cols: socket.assigns.cols,
          rows: socket.assigns.rows
        ]

        case TerminalSupervisor.start_session(server, opts) do
          {:ok, pid} ->
            assign(socket, session_pid: pid, error: nil)

          {:error, reason} ->
            err_str = "Failed to start terminal supervisor child: #{inspect(reason)}"
            ActivityLog.error(socket.assigns.server_id, err_str, reason)

            socket
            |> assign(connected: false, error: err_str)
            |> push_event("terminal_output", %{
              data: "\r\n\x1b[1;31m[Error]\x1b[0m #{err_str}\r\n"
            })
        end

      nil ->
        err_str = "Host '#{socket.assigns.server_id}' not found in configuration."
        ActivityLog.error(socket.assigns.server_id, err_str)

        socket
        |> assign(connected: false, error: err_str)
        |> push_event("terminal_output", %{
          data: "\r\n\x1b[1;31m[Configuration Error]\x1b[0m #{err_str}\r\n"
        })
    end
  end

  defp resolve_server_struct(server_id) do
    case ServerManager.get_server(server_id) do
      {:ok, snapshot} when is_map(snapshot) ->
        %Server{
          id: snapshot.id,
          name: snapshot.name || snapshot.id,
          host: snapshot.host,
          user: snapshot.user,
          port: snapshot.port || 22,
          proxy_jump: snapshot.proxy_jump
        }

      _ ->
        # Try loading directly from config file
        case Config.load_file(Config.default_config_path()) do
          {:ok, %Config{servers: servers}} ->
            Enum.find(servers, fn s -> s.id == server_id end)

          _ ->
            nil
        end
    end
  end

  defp format_error_reason({:connection_failed, reason}), do: "Connection failed: #{format_error_reason(reason)}"
  defp format_error_reason({:connect_failed, reason}), do: "Connect failed: #{format_error_reason(reason)}"
  defp format_error_reason({:pty_failed, reason}), do: "PTY allocation failed: #{format_error_reason(reason)}"
  defp format_error_reason(:econnrefused), do: "Connection refused (econnrefused) - check host & port 22"
  defp format_error_reason(:etimedout), do: "Connection timed out (etimedout)"
  defp format_error_reason(:nxdomain), do: "Host domain name cannot be resolved (nxdomain)"
  defp format_error_reason(:key_exchange_failed), do: "Key exchange / host key verification failed"
  defp format_error_reason(:auth_failed), do: "Authentication failed - public key or password rejected"
  defp format_error_reason('Host key not accepted'), do: "Host key not accepted"
  defp format_error_reason(str) when is_binary(str), do: str
  defp format_error_reason(other), do: inspect(other)
end
