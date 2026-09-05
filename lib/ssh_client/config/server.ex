defmodule SSHClient.Config.Server do
  @moduledoc """
  Represents a remote server target for monitoring and management.
  """

  alias SSHClient.Config.Check

  @enforce_keys [:id, :host]
  defstruct [
    :id,
    :name,
    :host,
    :user,
    :proxy_jump,
    port: 22,
    checks: []
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          name: String.t(),
          host: String.t(),
          user: String.t() | nil,
          port: pos_integer(),
          proxy_jump: String.t() | nil,
          checks: list(Check.t())
        }

  @doc """
  Builds and validates a Server struct from raw configuration data.
  """
  @spec from_map(map()) :: {:ok, t()} | {:error, String.t()}
  def from_map(attrs) when is_map(attrs) do
    with {:ok, host} <- fetch_host(attrs),
         {:ok, port} <- parse_port(attrs),
         {:ok, checks} <- parse_checks(attrs) do
      id = Map.get(attrs, "id") || host
      name = Map.get(attrs, "name") || id
      user = Map.get(attrs, "user")

      proxy_jump =
        Map.get(attrs, "ProxyJump") || Map.get(attrs, "proxy_jump") || Map.get(attrs, "proxyjump")

      server = %__MODULE__{
        id: to_string(id),
        name: to_string(name),
        host: to_string(host),
        user: user && to_string(user),
        port: port,
        proxy_jump: proxy_jump && to_string(proxy_jump),
        checks: checks
      }

      {:ok, server}
    end
  end

  def from_map(_invalid) do
    {:error, "server entry must be a map"}
  end

  defp fetch_host(%{"host" => host}) when is_binary(host) and byte_size(host) > 0 do
    {:ok, host}
  end

  defp fetch_host(%{"host" => _}) do
    {:error, "server host must be a non-empty string"}
  end

  defp fetch_host(_attrs) do
    {:error, "missing required field 'host' in server configuration"}
  end

  defp parse_port(%{"port" => port}) when is_integer(port) and port in 1..65535 do
    {:ok, port}
  end

  defp parse_port(%{"port" => port}) when is_binary(port) do
    case Integer.parse(port) do
      {int, ""} when int in 1..65535 -> {:ok, int}
      _ -> {:error, "invalid port number: #{port}"}
    end
  end

  defp parse_port(%{"port" => invalid}) do
    {:error, "invalid port number: #{inspect(invalid)}"}
  end

  defp parse_port(_attrs) do
    {:ok, 22}
  end

  defp parse_checks(%{"checks" => checks}) when is_list(checks) do
    Enum.reduce_while(checks, {:ok, []}, fn check_map, {:ok, acc} ->
      case Check.from_map(check_map) do
        {:ok, check} -> {:cont, {:ok, [check | acc]}}
        {:error, reason} -> {:halt, {:error, "invalid check in server: #{reason}"}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, Enum.reverse(list)}
      error -> error
    end
  end

  defp parse_checks(%{"checks" => _invalid}) do
    {:error, "'checks' must be a list"}
  end

  defp parse_checks(_attrs) do
    {:ok, []}
  end
end
