defmodule SSHClientWeb.TerminalLive do
  @moduledoc """
  Phoenix LiveView hosting the xterm.js embedded terminal for interactive SSH sessions.
  """

  use Phoenix.LiveView, layout: {SSHClientWeb.Layouts, :app}

  @impl true
  def mount(%{"id" => server_id}, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Terminal — #{server_id}")
      |> assign(:server_id, server_id)
      |> assign(:connected, false)
      |> assign(:cols, 80)
      |> assign(:rows, 24)

    {:ok, socket}
  end

  @impl true
  def handle_event("terminal_ready", _params, socket) do
    {:noreply, assign(socket, :connected, true)}
  end

  def handle_event("terminal_data", %{"data" => _data}, socket) do
    # Forward data to SSH PTY session via channel
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-screen bg-[#050505]">
      <!-- Terminal topbar -->
      <div class="h-10 flex items-center justify-between px-4 bg-[#0a0a0a] border-b border-[#1f1f1f] shrink-0">
        <div class="flex items-center gap-3">
          <a
            href="/"
            class="text-zinc-600 hover:text-zinc-400 text-xs font-mono transition-colors"
          >
            &larr; hosts
          </a>
          <span class="text-zinc-800">|</span>
          <span class="text-zinc-400 text-xs font-mono"><%= @server_id %></span>
        </div>
        <div class="flex items-center gap-2">
          <span class={["inline-flex items-center gap-1.5 text-[11px] font-mono",
            if(@connected, do: "text-emerald-400", else: "text-zinc-600")]}>
            <span class={["w-1.5 h-1.5 rounded-full",
              if(@connected, do: "bg-emerald-400 animate-pulse", else: "bg-zinc-700")]}></span>
            <%= if @connected, do: "connected", else: "connecting..." %>
          </span>
          <span class="text-zinc-700 text-[11px] font-mono"><%= @cols %>x<%= @rows %></span>
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

    <script>
      // TerminalHook — mounts xterm.js and wires to Phoenix channel
      window.TerminalHook = {
        mounted() {
          const el = this.el;
          const lv = this;

          if (typeof Terminal === 'undefined') {
            el.innerHTML = '<div style="color:#ef4444;font-family:monospace;padding:1rem">xterm.js not loaded</div>';
            return;
          }

          const term = new Terminal({
            cursorBlink: true,
            fontSize: 13,
            lineHeight: 1.25,
            fontFamily: "'JetBrains Mono', 'Menlo', 'Consolas', monospace",
            theme: {
              background: '#050505',
              foreground: '#e4e4e7',
              cursor:     '#3b82f6',
              black:      '#050505',
              brightBlack:'#27272a',
              red:        '#ef4444',
              blue:       '#3b82f6',
              cyan:       '#06b6d4',
              green:      '#22c55e',
              yellow:     '#eab308',
              white:      '#e4e4e7',
              brightWhite:'#fafafa'
            }
          });

          const fitAddon = (typeof FitAddon !== 'undefined') ? new FitAddon.FitAddon() : null;
          if (fitAddon) term.loadAddon(fitAddon);

          term.open(el);
          if (fitAddon) fitAddon.fit();

          term.writeln('\x1b[1;34mssh-client\x1b[0m \x1b[2mv0.0.1\x1b[0m');
          term.writeln('\x1b[2mConnecting to ' + (el.dataset.serverId || 'server') + '...\x1b[0m');
          term.writeln('');

          lv.pushEvent("terminal_ready", {});

          term.onData(function(data) {
            lv.pushEvent("terminal_data", { data: data });
          });

          window.addEventListener('resize', () => {
            if (fitAddon) fitAddon.fit();
          });
        }
      };
    </script>
    """
  end
end
