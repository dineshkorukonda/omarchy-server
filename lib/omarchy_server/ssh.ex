defmodule OmarchyServer.SSH do
  @moduledoc """
  SSH client wrapper built on OTP :ssh with ProxyJump support and typed error handling.
  """

  alias OmarchyServer.Config.Server

  defmodule Connection do
    @moduledoc """
    Represents an active SSH connection, tracking channel and optional jump host tunnel.
    """
    defstruct [:conn_ref, :jump_ref, :jump_port, :server]
  end

  @type t :: %Connection{
          conn_ref: :ssh.connection_ref(),
          jump_ref: :ssh.connection_ref() | nil,
          jump_port: integer() | nil,
          server: Server.t() | map()
        }

  @type exec_result :: {:ok, String.t(), integer()} | {:error, term()}

  @doc """
  Parses a ProxyJump string into %{host: String.t(), port: integer(), user: String.t() | nil}.
  Supports formats:
  - "host"
  - "user@host"
  - "user@host:port"
  - "host:port"
  """
  @spec parse_proxy_jump(String.t() | nil) ::
          %{host: String.t(), port: integer(), user: String.t() | nil} | nil
  def parse_proxy_jump(nil), do: nil
  def parse_proxy_jump(""), do: nil

  def parse_proxy_jump(jump_str) when is_binary(jump_str) do
    {user, rest} =
      case String.split(jump_str, "@", parts: 2) do
        [u, r] -> {u, r}
        [r] -> {nil, r}
      end

    {host, port} =
      case String.split(rest, ":", parts: 2) do
        [h, p] ->
          case Integer.parse(p) do
            {parsed_port, ""} -> {h, parsed_port}
            _ -> {h, 22}
          end

        [h] ->
          {h, 22}
      end

    %{host: host, port: port, user: user}
  end

  @doc """
  Connects to a remote server using OTP :ssh, establishing a jump host tunnel if configured.
  Returns `{:ok, %Connection{}}` or `{:error, typed_error}`.
  """
  @spec connect(Server.t() | map(), keyword()) :: {:ok, Connection.t()} | {:error, term()}
  def connect(server_or_opts, opts \\ [])

  def connect(%Server{} = server, opts) do
    proxy_jump = server.proxy_jump
    do_connect(server, proxy_jump, opts)
  end

  def connect(opts_map, opts) when is_map(opts_map) do
    proxy_jump = Map.get(opts_map, :proxy_jump) || Map.get(opts_map, "proxy_jump")
    do_connect(opts_map, proxy_jump, opts)
  end

  defp do_connect(target, nil, opts) do
    host = get_field(target, :host)
    port = get_field(target, :port, 22)
    user = get_field(target, :user)
    timeout = Keyword.get(opts, :timeout, 10_000)

    case connect_direct(host, port, user, timeout, opts) do
      {:ok, conn_ref} ->
        {:ok, %Connection{conn_ref: conn_ref, jump_ref: nil, jump_port: nil, server: target}}

      {:error, reason} ->
        {:error, {:connection_failed, reason}}
    end
  end

  defp do_connect(target, proxy_jump, opts) do
    jump_info = parse_proxy_jump(proxy_jump)
    timeout = Keyword.get(opts, :timeout, 10_000)

    case connect_direct(jump_info.host, jump_info.port, jump_info.user, timeout, opts) do
      {:ok, jump_ref} ->
        target_host = get_field(target, :host)
        target_port = get_field(target, :port, 22)
        target_user = get_field(target, :user)

        target_host_charlist = String.to_charlist(target_host)

        case :ssh.tcpip_tunnel_to_server(
               jump_ref,
               ~c"127.0.0.1",
               0,
               target_host_charlist,
               target_port
             ) do
          {:ok, listen_port} ->
            case connect_direct("127.0.0.1", listen_port, target_user, timeout, opts) do
              {:ok, conn_ref} ->
                {:ok,
                 %Connection{
                   conn_ref: conn_ref,
                   jump_ref: jump_ref,
                   jump_port: listen_port,
                   server: target
                 }}

              {:error, reason} ->
                :ssh.close(jump_ref)
                {:error, {:connection_failed, reason}}
            end

          {:error, reason} ->
            :ssh.close(jump_ref)
            {:error, {:jump_tunnel_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:jump_host_failed, reason}}
    end
  end

  defp connect_direct(host, port, user, timeout, opts) do
    host_charlist = ensure_charlist(host)
    ssh_opts = build_ssh_options(user, opts)

    try do
      :ssh.connect(host_charlist, port, ssh_opts, timeout)
    catch
      :exit, reason -> {:error, reason}
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp build_ssh_options(user, extra_opts) do
    base = [
      silently_accept_hosts: true,
      user_interaction: false
    ]

    base =
      if user && user != "" do
        [{:user, ensure_charlist(user)} | base]
      else
        base
      end

    user_dir =
      Keyword.get(extra_opts, :user_dir) ||
        Path.expand("~/.ssh")

    base =
      if File.dir?(user_dir) do
        [{:user_dir, ensure_charlist(user_dir)} | base]
      else
        base
      end

    if password = Keyword.get(extra_opts, :password) do
      [{:password, ensure_charlist(password)} | base]
    else
      base
    end
  end

  @doc """
  Executes a command on an open SSH connection and awaits completion.
  Returns `{:ok, stdout, exit_status}` or `{:error, typed_reason}`.
  """
  @spec exec(Connection.t(), String.t(), keyword()) :: exec_result()
  def exec(%Connection{conn_ref: conn_ref}, command, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 15_000)

    with {:ok, channel_id} <- open_session(conn_ref, timeout),
         status when status in [:ok, :success] <- send_exec(conn_ref, channel_id, command, timeout) do
      collect_output(conn_ref, channel_id, timeout)
    else
      {:error, reason} -> {:error, {:exec_failed, reason}}
      other -> {:error, {:exec_failed, other}}
    end
  end

  defp open_session(conn_ref, timeout) do
    try do
      :ssh_connection.session_channel(conn_ref, timeout)
    catch
      :exit, reason -> {:error, reason}
      kind, reason -> {:error, {kind, reason}}
    end
  end

  defp send_exec(conn_ref, channel_id, command, timeout) do
    try do
      :ssh_connection.exec(conn_ref, channel_id, ensure_charlist(command), timeout)
    catch
      :exit, reason -> {:error, reason}
      kind, reason -> {:error, {kind, reason}}
    end
  end

  @doc """
  Collects channel messages until the channel closes or reaches timeout.
  """
  @spec collect_output(term(), term(), non_neg_integer()) :: exec_result()
  def collect_output(conn_ref, channel_id, timeout) do
    do_collect(conn_ref, channel_id, [], 0, timeout)
  end

  defp do_collect(conn_ref, channel_id, acc, exit_code, timeout) do
    receive do
      {:ssh_cm, ^conn_ref, {:data, ^channel_id, _type, data}} ->
        do_collect(conn_ref, channel_id, [data | acc], exit_code, timeout)

      {:ssh_cm, ^conn_ref, {:exit_status, ^channel_id, status}} ->
        do_collect(conn_ref, channel_id, acc, status, timeout)

      {:ssh_cm, ^conn_ref, {:eof, ^channel_id}} ->
        do_collect(conn_ref, channel_id, acc, exit_code, timeout)

      {:ssh_cm, ^conn_ref, {:closed, ^channel_id}} ->
        full_output =
          acc
          |> Enum.reverse()
          |> IO.iodata_to_binary()

        {:ok, full_output, exit_code}
    after
      timeout ->
        try do
          :ssh_connection.close(conn_ref, channel_id)
        catch
          _, _ -> :ok
        end

        {:error, :timeout}
    end
  end

  @doc """
  Closes an active SSH connection, its jump tunnel, and jump host connection if present.
  """
  @spec close(Connection.t() | term()) :: :ok
  def close(%Connection{conn_ref: conn_ref, jump_ref: jump_ref}) do
    if conn_ref, do: :ssh.close(conn_ref)
    if jump_ref, do: :ssh.close(jump_ref)
    :ok
  rescue
    _ -> :ok
  end

  def close(_), do: :ok

  @doc """
  Runs a command by opening a connection, executing the command, and closing the connection.
  """
  @spec run(Server.t() | map(), String.t(), keyword()) :: exec_result()
  def run(server_or_opts, command, opts \\ []) do
    case connect(server_or_opts, opts) do
      {:ok, conn} ->
        try do
          exec(conn, command, opts)
        after
          close(conn)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp get_field(map_or_struct, key, default \\ nil)

  defp get_field(%Server{} = s, :host, _), do: s.host
  defp get_field(%Server{} = s, :port, _), do: s.port || 22
  defp get_field(%Server{} = s, :user, _), do: s.user
  defp get_field(%Server{} = s, :proxy_jump, _), do: s.proxy_jump

  defp get_field(m, key, default) when is_map(m) do
    Map.get(m, key) || Map.get(m, to_string(key)) || default
  end

  defp ensure_charlist(val) when is_binary(val), do: String.to_charlist(val)
  defp ensure_charlist(val) when is_list(val), do: val
end
