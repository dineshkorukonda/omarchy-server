defmodule SSHClient.ServiceChecks do
  @moduledoc """
  Performs service status checks for systemctl, pm2, and docker.
  Returns running, stopped, unknown, or skipped (when tool is not installed).
  """

  alias SSHClient.Config.Check
  alias SSHClient.SSH

  @type status :: :running | :stopped | :unknown | :skipped

  @doc """
  Builds the shell command used to check service status.
  """
  @spec build_command(atom() | String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def build_command(type, name) when is_atom(type) do
    build_command(to_string(type), name)
  end

  def build_command("systemctl", name) when is_binary(name) do
    safe_name = sanitize_name(name)

    cmd =
      "sh -c 'if ! command -v systemctl >/dev/null 2>&1; then echo \"missing\"; exit 0; fi; " <>
        "state=$(systemctl is-active \"#{safe_name}\" 2>/dev/null || true); " <>
        "case \"$state\" in active) echo running;; inactive|failed|deactivating) echo stopped;; \"\") echo stopped;; *) echo unknown;; esac'"

    {:ok, cmd}
  end

  def build_command("docker", name) when is_binary(name) do
    safe_name = sanitize_name(name)

    cmd =
      "sh -c 'if ! command -v docker >/dev/null 2>&1; then echo \"missing\"; exit 0; fi; " <>
        "state=$(docker inspect -f \"{{.State.Status}}\" \"#{safe_name}\" 2>/dev/null || true); " <>
        "case \"$state\" in running) echo running;; exited|dead|paused|created) echo stopped;; \"\") echo stopped;; *) echo unknown;; esac'"

    {:ok, cmd}
  end

  def build_command("pm2", name) when is_binary(name) do
    safe_name = sanitize_name(name)

    cmd =
      "sh -c 'if ! command -v pm2 >/dev/null 2>&1; then echo \"missing\"; exit 0; fi; " <>
        "state=$(pm2 describe \"#{safe_name}\" 2>/dev/null | grep -i \"status\" | head -n 1 | awk \"{print \\$4}\" || true); " <>
        "case \"$state\" in online) echo running;; stopped|errored|stopping) echo stopped;; \"\") echo stopped;; *) echo unknown;; esac'"

    {:ok, cmd}
  end

  def build_command(other, _name) do
    {:error, "unsupported check type: #{other}"}
  end

  @doc """
  Parses raw check output into a status atom.
  """
  @spec parse_status(String.t() | nil) :: status()
  def parse_status(output) when is_binary(output) do
    trimmed =
      output
      |> String.trim()
      |> String.downcase()

    cond do
      trimmed == "missing" -> :skipped
      trimmed == "running" -> :running
      trimmed == "stopped" -> :stopped
      true -> :unknown
    end
  end

  def parse_status(_other), do: :unknown

  @doc """
  Executes a single check using an SSH connection or runner function.
  """
  @spec check(Check.t() | map(), term(), keyword()) :: {:ok, status()} | {:error, term()}
  def check(check_spec, runner_or_conn, opts \\ [])

  def check(%Check{type: type, name: name}, runner_or_conn, opts) do
    with {:ok, cmd} <- build_command(type, name),
         {:ok, output} <- run_command(runner_or_conn, cmd, opts) do
      {:ok, parse_status(output)}
    end
  end

  def check(%{"type" => type, "name" => name}, runner_or_conn, opts) do
    check(%Check{type: String.to_atom(to_string(type)), name: name}, runner_or_conn, opts)
  end

  @doc """
  Executes a list of checks and returns a status map keyed by check name.
  """
  @spec check_all(list(Check.t() | map()), term(), keyword()) ::
          {:ok, %{String.t() => %{type: atom(), name: String.t(), status: status()}}}
          | {:error, term()}
  def check_all(checks, runner_or_conn, opts \\ []) when is_list(checks) do
    Enum.reduce_while(checks, {:ok, %{}}, fn check_spec, {:ok, acc} ->
      name = get_check_name(check_spec)
      type = get_check_type(check_spec)

      case check(check_spec, runner_or_conn, opts) do
        {:ok, status} ->
          result = %{type: type, name: name, status: status}
          {:cont, {:ok, Map.put(acc, name, result)}}

        {:error, reason} ->
          {:halt, {:error, {:check_failed, name, reason}}}
      end
    end)
  end

  defp run_command(runner, cmd, _opts) when is_function(runner, 1) do
    case runner.(cmd) do
      {:ok, output, _code} -> {:ok, output}
      {:ok, output} when is_binary(output) -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_command(%SSH.Connection{} = conn, cmd, opts) do
    timeout = Keyword.get(opts, :timeout, 10_000)

    case SSH.exec(conn, cmd, timeout: timeout) do
      {:ok, output, _code} -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  defp run_command(_other, _cmd, _opts) do
    {:error, :invalid_runner_or_connection}
  end

  defp get_check_name(%Check{name: name}), do: name
  defp get_check_name(%{"name" => name}), do: name
  defp get_check_name(%{name: name}), do: name

  defp get_check_type(%Check{type: type}), do: type
  defp get_check_type(%{"type" => type}), do: String.to_atom(to_string(type))
  defp get_check_type(%{type: type}), do: type

  defp sanitize_name(name) do
    # Strip dangerous shell characters
    String.replace(name, ~r/[^\w\.\-\@\:\/]/, "")
  end
end
