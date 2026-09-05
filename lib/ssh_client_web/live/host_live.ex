defmodule SSHClientWeb.HostLive do
  @moduledoc """
  Phoenix LiveView component rendering the host list and live status UI,
  achieving parity with the original Omarchy QML panel.
  """

  alias SSHClient.ServerManager
  alias SSHClient.ServerWorker

  @doc """
  Returns the initial state for the host list view.
  """
  def initial_state do
    servers = list_servers()

    %{
      servers: servers,
      selected_server: List.first(servers),
      filter: "",
      add_server_modal: false,
      loading: false,
      error: nil
    }
  end

  @doc """
  Fetches and formats the list of all registered servers and their live state.
  """
  def list_servers do
    servers =
      try do
        ServerManager.list_servers()
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end

    Enum.map(servers, &format_server/1)
  end

  @doc """
  Triggers a manual refresh/poll for a specific server or all servers.
  """
  def refresh_server(server_id) do
    case ServerWorker.whereis(server_id) do
      pid when is_pid(pid) ->
        ServerWorker.poll_now(pid)

      nil ->
        {:error, :not_found}
    end
  end

  def refresh_all do
    workers =
      try do
        ServerManager.get_workers()
      rescue
        _ -> %{}
      catch
        :exit, _ -> %{}
      end

    Enum.each(workers, fn {_id, pid} ->
      try do
        ServerWorker.poll_now(pid)
      rescue
        _ -> :ok
      catch
        :exit, _ -> :ok
      end
    end)

    :ok
  end

  @doc """
  Selects a server by ID for viewing details.
  """
  def select_server(state, server_id) do
    selected = Enum.find(state.servers, fn s -> s.id == server_id end)
    %{state | selected_server: selected}
  end

  @doc """
  Filters and ranks the server list based on a query string using fuzzy subsequence
  and substring matching across name, host, id, and optional group/tags.
  If group filter is provided, narrows down to that group first.
  """
  def filter_servers(servers, query, group_filter \\ nil) do
    filtered_by_group =
      case group_filter do
        nil -> servers
        "" -> servers
        g -> Enum.filter(servers, fn s -> s[:group] == g or Map.get(s, "group") == g end)
      end

    case String.trim(to_string(query)) do
      "" ->
        filtered_by_group

      q ->
        q_down = String.downcase(q)

        filtered_by_group
        |> Enum.map(fn s -> {s, fuzzy_score(s, q_down)} end)
        |> Enum.filter(fn {_s, score} -> score > 0 end)
        |> Enum.sort_by(fn {_s, score} -> score end, :desc)
        |> Enum.map(fn {s, _score} -> s end)
    end
  end

  @doc """
  Computes a fuzzy matching score between a server candidate and a query string.
  Higher scores indicate stronger matches (exact prefix > substring > subsequence).
  """
  def fuzzy_score(server, query) when is_binary(query) do
    target_str =
      [server[:name], server[:host], server[:id], server[:group]]
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.downcase/1)
      |> Enum.join(" ")

    cond do
      target_str == query ->
        1000

      String.starts_with?(target_str, query) ->
        500

      String.contains?(target_str, query) ->
        200 + (100 - min(String.length(target_str), 100))

      subsequence_match?(String.to_charlist(query), String.to_charlist(target_str)) ->
        50

      true ->
        0
    end
  end

  defp subsequence_match?([], _target), do: true
  defp subsequence_match?(_pattern, []), do: false

  defp subsequence_match?([char | p_rest], [char | t_rest]) do
    subsequence_match?(p_rest, t_rest)
  end

  defp subsequence_match?(pattern, [_ | t_rest]) do
    subsequence_match?(pattern, t_rest)
  end

  @doc """
  Formats server metrics and status into a display-ready structure.
  """
  def format_server(server) when is_map(server) do
    status = normalize_status(server[:status])
    metrics = server[:metrics] || %{}
    checks = server[:checks] || %{}

    %{
      id: to_string(server[:id]),
      name: to_string(server[:name] || server[:id]),
      host: to_string(server[:host] || ""),
      status: status,
      status_badge_color: badge_color_for_status(status),
      cpu_percent: Map.get(metrics, :cpu_percent, Map.get(metrics, "cpu_percent", 0.0)),
      ram_percent: Map.get(metrics, :ram_percent, Map.get(metrics, "ram_percent", 0.0)),
      disk_percent: Map.get(metrics, :disk_percent, Map.get(metrics, "disk_percent", 0.0)),
      uptime: Map.get(metrics, :uptime, Map.get(metrics, "uptime", "unknown")),
      checks: checks,
      init_system: server[:init_system],
      last_error: server[:last_error],
      updated_at: server[:updated_at]
    }
  end

  @doc """
  Renders the HTML structure for the host list view (LiveView template).
  """
  def render_html(assigns) do
    servers = filter_servers(assigns.servers, assigns.filter)

    server_rows =
      Enum.map(servers, fn server ->
        """
        <tr class="host-row hover:bg-zinc-800/50 cursor-pointer" data-id="\#{server.id}">
          <td class="px-4 py-3 font-medium text-white">\#{server.name}</td>
          <td class="px-4 py-3 text-zinc-400 font-mono text-sm">\#{server.host}</td>
          <td class="px-4 py-3">
            <span class="inline-flex items-center px-2 py-0.5 rounded text-xs font-medium \#{server.status_badge_color}">
              \#{server.status}
            </span>
          </td>
          <td class="px-4 py-3 text-zinc-300 text-sm">\#{server.cpu_percent}%</td>
          <td class="px-4 py-3 text-zinc-300 text-sm">\#{server.ram_percent}%</td>
          <td class="px-4 py-3 text-zinc-300 text-sm">\#{server.disk_percent}%</td>
          <td class="px-4 py-3 text-right">
            <button class="px-2 py-1 bg-zinc-700 hover:bg-zinc-600 text-white rounded text-xs" phx-click="poll_now" phx-value-id="\#{server.id}">
              Refresh
            </button>
            <button class="ml-2 px-2 py-1 bg-blue-600 hover:bg-blue-500 text-white rounded text-xs" phx-click="connect" phx-value-id="\#{server.id}">
              Terminal
            </button>
          </td>
        </tr>
        """
      end)
      |> Enum.join("\n")

    """
    <div class="flex flex-col h-full bg-zinc-950 text-zinc-100 font-sans">
      <!-- Header -->
      <div class="flex items-center justify-between px-6 py-4 border-b border-zinc-800">
        <h1 class="text-lg font-semibold tracking-tight text-white">Hosts & Status</h1>
        <div class="flex items-center gap-3">
          <input
            type="text"
            placeholder="Search hosts..."
            value="\#{assigns.filter}"
            class="px-3 py-1.5 bg-zinc-900 border border-zinc-700 rounded-md text-sm text-zinc-200 focus:outline-none focus:border-blue-500"
            phx-keyup="search"
          />
          <button class="px-3 py-1.5 bg-blue-600 hover:bg-blue-500 text-white font-medium text-sm rounded-md" phx-click="open_add_modal">
            + Add Host
          </button>
          <button class="px-3 py-1.5 bg-zinc-800 hover:bg-zinc-700 text-zinc-300 font-medium text-sm rounded-md" phx-click="poll_all">
            Refresh All
          </button>
        </div>
      </div>

      <!-- Main Table -->
      <div class="flex-1 overflow-auto">
        <table class="w-full text-left border-collapse">
          <thead>
            <tr class="border-b border-zinc-800 text-xs font-semibold text-zinc-400 uppercase tracking-wider bg-zinc-900/60">
              <th class="px-4 py-3">Host Name</th>
              <th class="px-4 py-3">Address</th>
              <th class="px-4 py-3">Status</th>
              <th class="px-4 py-3">CPU</th>
              <th class="px-4 py-3">RAM</th>
              <th class="px-4 py-3">Disk</th>
              <th class="px-4 py-3 text-right">Actions</th>
            </tr>
          </thead>
          <tbody class="divide-y divide-zinc-800/60">
            \#{server_rows}
          </tbody>
        </table>
      </div>
    </div>
    """
  end

  defp normalize_status(status) when is_atom(status), do: Atom.to_string(status)
  defp normalize_status(status) when is_binary(status), do: status
  defp normalize_status(_), do: "unknown"

  defp badge_color_for_status("polling"), do: "bg-emerald-500/20 text-emerald-400"
  defp badge_color_for_status("connecting"), do: "bg-blue-500/20 text-blue-400"
  defp badge_color_for_status("degraded"), do: "bg-amber-500/20 text-amber-400"
  defp badge_color_for_status("reconnecting"), do: "bg-purple-500/20 text-purple-400"
  defp badge_color_for_status(_), do: "bg-zinc-500/20 text-zinc-400"
end
