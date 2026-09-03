defmodule OmarchyServer.Config do
  @moduledoc """
  Loads and validates servers.yaml configuration for omarchy-server.
  """

  alias OmarchyServer.Config.Server

  defstruct servers: []

  @type t :: %__MODULE__{
          servers: list(Server.t())
        }

  defmodule Error do
    defexception [:message]
  end

  @doc """
  Loads and parses configuration from a YAML file path.
  """
  @spec load_file(Path.t()) :: {:ok, t()} | {:error, String.t()}
  def load_file(path) when is_binary(path) do
    case File.read(path) do
      {:ok, content} ->
        load_string(content)

      {:error, reason} ->
        {:error, "failed to read config file '#{path}': #{:file.format_error(reason)}"}
    end
  end

  @doc """
  Loads and parses configuration from a YAML file path, raising on error.
  """
  @spec load_file!(Path.t()) :: t()
  def load_file!(path) do
    case load_file(path) do
      {:ok, config} -> config
      {:error, reason} -> raise Error, message: reason
    end
  end

  @doc """
  Loads and parses configuration from a YAML string.
  """
  @spec load_string(String.t()) :: {:ok, t()} | {:error, String.t()}
  def load_string(yaml_string) when is_binary(yaml_string) do
    case YamlElixir.read_from_string(yaml_string) do
      {:ok, data} ->
        parse_data(data)

      {:error, %YamlElixir.ParsingError{message: message}} ->
        {:error, "invalid YAML syntax: #{message}"}

      {:error, reason} ->
        {:error, "invalid YAML: #{inspect(reason)}"}
    end
  end

  @doc """
  Loads and parses configuration from a YAML string, raising on error.
  """
  @spec load_string!(String.t()) :: t()
  def load_string!(yaml_string) do
    case load_string(yaml_string) do
      {:ok, config} -> config
      {:error, reason} -> raise Error, message: reason
    end
  end

  defp parse_data(%{"servers" => servers}) when is_list(servers) do
    parse_servers_list(servers)
  end

  defp parse_data(servers) when is_list(servers) do
    parse_servers_list(servers)
  end

  defp parse_data(%{}) do
    {:error, "config must contain a 'servers' key with a list of servers"}
  end

  defp parse_data(nil) do
    {:error, "config is empty"}
  end

  defp parse_data(_invalid) do
    {:error, "config must be a map with a 'servers' key or a list of servers"}
  end

  defp parse_servers_list(servers) do
    Enum.reduce_while(servers, {:ok, []}, fn server_data, {:ok, acc} ->
      case Server.from_map(server_data) do
        {:ok, server} -> {:cont, {:ok, [server | acc]}}
        {:error, reason} -> {:halt, {:error, "invalid server entry: #{reason}"}}
      end
    end)
    |> case do
      {:ok, list} -> {:ok, %__MODULE__{servers: Enum.reverse(list)}}
      error -> error
    end
  end
end
