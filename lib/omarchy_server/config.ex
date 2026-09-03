defmodule OmarchyServer.Config do
  @moduledoc """
  Loads and validates servers.yaml configuration for omarchy-server.
  """

  alias OmarchyServer.Config.Check
  alias OmarchyServer.Config.Server

  defstruct servers: []

  @type t :: %__MODULE__{
          servers: list(Server.t())
        }

  defmodule Error do
    defexception [:message]
  end

  @doc """
  Returns the default servers.yaml config file path.
  Priority:
  1. System env OMARCHY_SERVERS_CONFIG
  2. ~/.config/omarchy/servers.yaml
  3. servers.yaml in current working directory (if it exists)
  4. ~/.config/omarchy/servers.yaml
  """
  @spec default_config_path() :: Path.t()
  def default_config_path do
    cond do
      env_path = System.get_env("OMARCHY_SERVERS_CONFIG") ->
        Path.expand(env_path)

      File.exists?(Path.expand("~/.config/omarchy/servers.yaml")) ->
        Path.expand("~/.config/omarchy/servers.yaml")

      File.exists?("servers.yaml") ->
        Path.expand("servers.yaml")

      true ->
        Path.expand("~/.config/omarchy/servers.yaml")
    end
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
  Saves a Config struct or list of servers to a YAML file path.
  Creates parent directories if necessary.
  """
  @spec save_file(t() | list(Server.t()), Path.t()) :: :ok | {:error, String.t()}
  def save_file(config_or_servers, path) when is_binary(path) do
    yaml_content = dump_string(config_or_servers)

    with :ok <- File.mkdir_p(Path.dirname(path)),
         :ok <- File.write(path, yaml_content) do
      :ok
    else
      {:error, reason} ->
        {:error, "failed to write config file '#{path}': #{:file.format_error(reason)}"}
    end
  end

  @doc """
  Serializes a Config struct or list of servers into a YAML formatted string.
  """
  @spec dump_string(t() | list(Server.t())) :: String.t()
  def dump_string(%__MODULE__{servers: servers}) do
    dump_string(servers)
  end

  def dump_string([]) do
    "servers: []\n"
  end

  def dump_string(servers) when is_list(servers) do
    lines = ["servers:"]

    server_blocks =
      Enum.map(servers, fn %Server{} = s ->
        dump_server(s)
      end)

    Enum.join(lines ++ server_blocks, "\n") <> "\n"
  end

  defp dump_server(%Server{} = s) do
    fields = [
      "  - id: #{s.id}",
      "    name: #{inspect(s.name || s.id)}",
      "    host: #{s.host}",
      "    port: #{s.port || 22}"
    ]

    fields =
      if s.user do
        fields ++ ["    user: #{s.user}"]
      else
        fields
      end

    fields =
      if s.proxy_jump do
        fields ++ ["    proxy_jump: #{s.proxy_jump}"]
      else
        fields
      end

    fields =
      if s.checks && s.checks != [] do
        check_lines =
          Enum.flat_map(s.checks, fn %Check{} = c ->
            [
              "      - type: #{c.type}",
              "        name: #{c.name}"
            ]
          end)

        fields ++ ["    checks:"] ++ check_lines
      else
        fields
      end

    Enum.join(fields, "\n")
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
