defmodule OmarchyServer.SocketAPI do
  @moduledoc """
  Unix domain socket server exposing server states and monitoring data as JSON.
  """

  use GenServer

  alias OmarchyServer.ServerManager

  @default_socket_path "/tmp/omarchy_server.sock"
  @name __MODULE__

  defstruct [
    :socket_path,
    :listen_socket,
    :acceptor_pid
  ]

  # Client API

  @doc """
  Starts the SocketAPI server on a Unix domain socket.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Returns the default socket path.
  """
  def default_socket_path do
    System.get_env("OMARCHY_SERVER_SOCKET") || @default_socket_path
  end

  # Server Callbacks

  @impl true
  def init(opts) do
    socket_path = Keyword.get(opts, :socket_path, default_socket_path())
    clean_existing_socket(socket_path)

    charlist_path = String.to_charlist(socket_path)

    socket_opts = [
      :binary,
      :local,
      {:ifaddr, {:local, charlist_path}},
      {:active, false},
      {:reuseaddr, true}
    ]

    case :gen_tcp.listen(0, socket_opts) do
      {:ok, listen_socket} ->
        state = %__MODULE__{
          socket_path: socket_path,
          listen_socket: listen_socket
        }

        acceptor_pid = spawn_link(fn -> accept_loop(listen_socket) end)
        {:ok, %{state | acceptor_pid: acceptor_pid}}

      {:error, reason} ->
        {:stop, {:listen_failed, reason}}
    end
  end

  @impl true
  def terminate(_reason, state) do
    if state.listen_socket, do: :gen_tcp.close(state.listen_socket)
    if state.socket_path, do: clean_existing_socket(state.socket_path)
    :ok
  end

  # Acceptor and Protocol Loop

  defp accept_loop(listen_socket) do
    case :gen_tcp.accept(listen_socket) do
      {:ok, client_socket} ->
        spawn(fn -> handle_client(client_socket) end)
        accept_loop(listen_socket)

      {:error, :closed} ->
        :ok

      {:error, _reason} ->
        accept_loop(listen_socket)
    end
  end

  defp handle_client(client_socket) do
    case :gen_tcp.recv(client_socket, 0, 500) do
      {:ok, data} ->
        response = process_request(data)
        send_json_response(client_socket, response)

      {:error, :timeout} ->
        response = get_all_servers_response()
        send_json_response(client_socket, response)

      {:error, _reason} ->
        :ok
    end

    :gen_tcp.close(client_socket)
  end

  defp process_request(data) when is_binary(data) do
    trimmed = String.trim(data)

    cond do
      trimmed == "" or trimmed == "GET" or String.starts_with?(trimmed, "GET ") ->
        get_all_servers_response()

      String.starts_with?(trimmed, "{") ->
        case decode_json(trimmed) do
          {:ok, %{"command" => "get_server", "server_id" => id}} ->
            case ServerManager.get_server(id) do
              {:ok, server} -> %{status: "ok", server: serialize_server(server)}
              {:error, reason} -> %{status: "error", error: to_string(reason)}
            end

          {:ok, %{"command" => "reload"}} ->
            case ServerManager.sync_file() do
              {:ok, result} -> %{status: "ok", reloaded: true, summary: result}
              {:error, reason} -> %{status: "error", error: inspect(reason)}
            end

          _ ->
            get_all_servers_response()
        end

      true ->
        get_all_servers_response()
    end
  end

  defp get_all_servers_response do
    servers =
      try do
        ServerManager.list_servers()
      rescue
        _ -> []
      catch
        :exit, _ -> []
      end

    serialized = Enum.map(servers, &serialize_server/1)

    %{
      status: "ok",
      servers: serialized,
      count: length(serialized),
      timestamp: DateTime.to_iso8601(DateTime.utc_now())
    }
  end

  defp serialize_server(server) when is_map(server) do
    %{
      id: to_string(server.id),
      name: to_string(server[:name] || server.id),
      host: to_string(server.host),
      status: to_string(server.status),
      metrics: server[:metrics] || %{},
      checks: server[:checks] || %{},
      init_system: server[:init_system] && to_string(server[:init_system]),
      last_error: server[:last_error] && inspect(server[:last_error]),
      updated_at: server[:updated_at] && DateTime.to_iso8601(server[:updated_at])
    }
  end

  defp send_json_response(socket, response_map) do
    json_binary =
      response_map
      |> :json.encode()
      |> IO.iodata_to_binary()

    :gen_tcp.send(socket, [json_binary, "\n"])
  end

  defp decode_json(binary) do
    try do
      {:ok, :json.decode(binary)}
    rescue
      _ -> :error
    end
  end

  defp clean_existing_socket(path) when is_binary(path) do
    File.mkdir_p!(Path.dirname(path))
    File.rm(path)
    :ok
  end
end
