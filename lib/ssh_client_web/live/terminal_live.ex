defmodule SSHClientWeb.TerminalLive do
  @moduledoc """
  Phoenix LiveView component hosting the xterm.js embedded terminal widget
  for interactive terminal sessions.
  """

  @doc """
  Returns the initial state for the terminal view.
  """
  def initial_state(opts \\ []) do
    server_id = Keyword.get(opts, :server_id, "local")
    title = Keyword.get(opts, :title, "Terminal")

    %{
      server_id: server_id,
      title: title,
      connected: false,
      theme: %{
        background: "#09090b",
        foreground: "#f4f4f5",
        cursor: "#3b82f6"
      },
      cols: 80,
      rows: 24
    }
  end

  @doc """
  Renders the HTML container and JavaScript initialization hook for xterm.js.
  """
  def render_html(assigns) do
    """
    <div class="flex flex-col h-full bg-zinc-950 text-zinc-100 font-sans" id="terminal-wrapper">
      <!-- Terminal Tab Bar -->
      <div class="flex items-center justify-between px-4 py-2 bg-zinc-900 border-b border-zinc-800 select-none">
        <div class="flex items-center gap-2">
          <div class="flex gap-1.5 mr-2">
            <span class="w-3 h-3 rounded-full bg-red-500/80 inline-block"></span>
            <span class="w-3 h-3 rounded-full bg-amber-500/80 inline-block"></span>
            <span class="w-3 h-3 rounded-full bg-emerald-500/80 inline-block"></span>
          </div>
          <span class="font-mono text-xs text-zinc-300 font-semibold">#{assigns.title}</span>
        </div>
        <div class="flex items-center gap-2 text-xs text-zinc-400">
          <span class="px-2 py-0.5 rounded bg-zinc-800 font-mono text-[11px]">80x24</span>
        </div>
      </div>

      <!-- xterm.js Container -->
      <div
        id="xterm-container"
        phx-hook="TerminalHook"
        class="flex-1 w-full h-full p-2 bg-zinc-950 overflow-hidden"
        data-cols="#{assigns.cols}"
        data-rows="#{assigns.rows}"
      ></div>

      <!-- Script Embed for standalone rendering -->
      <script>
        window.initXterm = function(el) {
          if (typeof Terminal === 'undefined') return;
          const term = new Terminal({
            cursorBlink: true,
            theme: {
              background: '#09090b',
              foreground: '#f4f4f5',
              cursor: '#3b82f6'
            },
            fontFamily: 'Menlo, Monaco, Consolas, "Courier New", monospace',
            fontSize: 13,
            lineHeight: 1.2
          });
          term.open(el);
          term.writeln('\\x1b[1;34mssh-client\\x1b[0m — interactive terminal');
          term.writeln('Type to test local input echo:');
          term.onData(function(data) {
            term.write(data);
          });
          return term;
        };
      </script>
    </div>
    """
  end
end
