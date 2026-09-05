defmodule SSHClient.Metrics do
  @moduledoc """
  Collects and parses host metrics (CPU, memory, disk) from standard Linux CLI tools.
  Parses top, free -m, and df -h output into structured maps.
  """

  alias SSHClient.SSH

  @combined_delimiter_free "===SSH_CLIENT_FREE==="
  @combined_delimiter_df "===SSH_CLIENT_DF==="
  @legacy_delimiter_free "===OMARCHY_FREE==="
  @legacy_delimiter_df "===OMARCHY_DF==="

  @doc """
  Command string combining top, free, and df into a single remote execution.
  """
  def combined_command do
    "LC_ALL=C top -bn1 | head -n 15; echo '#{@combined_delimiter_free}'; LC_ALL=C free -m; echo '#{@combined_delimiter_df}'; LC_ALL=C df -h -P"
  end

  @doc """
  Collects metrics from a server using an SSH connection or runner function.
  """
  def collect(conn_or_runner, opts \\ [])

  def collect(runner, _opts) when is_function(runner, 1) do
    case runner.(combined_command()) do
      {:ok, output, _code} -> parse_combined(output)
      {:ok, output} when is_binary(output) -> parse_combined(output)
      {:error, reason} -> {:error, {:metrics_collection_failed, reason}}
    end
  end

  def collect(%SSH.Connection{} = conn, opts) do
    timeout = Keyword.get(opts, :timeout, 10_000)

    case SSH.exec(conn, combined_command(), timeout: timeout) do
      {:ok, output, _code} -> parse_combined(output)
      {:error, reason} -> {:error, {:metrics_collection_failed, reason}}
    end
  end

  @doc """
  Parses combined output containing top, free, and df delimited sections.
  """
  def parse_combined(output) when is_binary(output) do
    delim_free =
      if String.contains?(output, @combined_delimiter_free),
        do: @combined_delimiter_free,
        else: @legacy_delimiter_free

    delim_df =
      if String.contains?(output, @combined_delimiter_df),
        do: @combined_delimiter_df,
        else: @legacy_delimiter_df

    case String.split(output, delim_free) do
      [top_part, rest] ->
        case String.split(rest, delim_df) do
          [free_part, df_part] ->
            with {:ok, cpu} <- parse_top(top_part),
                 {:ok, memory} <- parse_free(free_part),
                 {:ok, disk} <- parse_df(df_part) do
              {:ok, %{cpu: cpu, memory: memory, disk: disk}}
            end

          _ ->
            {:error, "failed to locate disk section in metrics output"}
        end

      _ ->
        {:error, "failed to locate free section in metrics output"}
    end
  end

  @doc """
  Parses `top` or `top -bn1` output into CPU metrics.
  """
  def parse_top(output) when is_binary(output) do
    lines = String.split(output, ~r/\r?\n/)

    cpu_stats =
      Enum.find_value(lines, fn line ->
        cond do
          String.contains?(line, "Cpu(s):") or String.contains?(line, "%Cpu(s):") ->
            parse_cpu_line(line)

          String.contains?(line, "CPU:") and String.contains?(line, "idle") ->
            parse_busybox_cpu_line(line)

          true ->
            nil
        end
      end)

    load_stats =
      Enum.find_value(lines, fn line ->
        if String.contains?(String.downcase(line), "load average:") do
          parse_load_line(line)
        end
      end) || %{load_1: 0.0, load_5: 0.0, load_15: 0.0}

    case cpu_stats do
      nil ->
        {:error, "unable to parse CPU stats from top output"}

      stats ->
        {:ok, Map.merge(stats, load_stats)}
    end
  end

  defp parse_cpu_line(line) do
    after_colon =
      case String.split(line, ":", parts: 2) do
        [_, val] -> val
        [val] -> val
      end

    parts =
      after_colon
      |> String.split(",")
      |> Enum.map(&String.trim/1)

    data =
      Enum.reduce(parts, %{}, fn part, acc ->
        case Regex.run(~r/([\d\.]+)\s*%?\s*([a-z]+)/, part) do
          [_, num_str, label] ->
            {num, _} = Float.parse(num_str)
            Map.put(acc, label, num)

          _ ->
            acc
        end
      end)

    idle = Map.get(data, "id", 100.0)
    user = Map.get(data, "us", 0.0)
    system = Map.get(data, "sy", 0.0)
    iowait = Map.get(data, "wa", 0.0)
    used = Float.round(max(0.0, 100.0 - idle), 1)

    %{
      used_percent: used,
      user: user,
      system: system,
      idle: idle,
      iowait: iowait
    }
  end

  defp parse_busybox_cpu_line(line) do
    # Format: CPU:  12% usr   3% sys   0% nic  85% idle   0% io
    parts = Regex.scan(~r/(\d+)%\s+([a-z]+)/, line)

    data =
      Enum.reduce(parts, %{}, fn [_, num_str, label], acc ->
        Map.put(acc, label, String.to_integer(num_str) * 1.0)
      end)

    idle = Map.get(data, "idle", 100.0)
    user = Map.get(data, "usr", 0.0)
    system = Map.get(data, "sys", 0.0)
    iowait = Map.get(data, "io", 0.0)
    used = Float.round(max(0.0, 100.0 - idle), 1)

    %{
      used_percent: used,
      user: user,
      system: system,
      idle: idle,
      iowait: iowait
    }
  end

  defp parse_load_line(line) do
    case String.split(line, ~r/load average:/i, parts: 2) do
      [_, loads_str] ->
        case Regex.scan(~r/([\d\.]+)/, loads_str) do
          [[_, l1], [_, l5], [_, l15] | _] ->
            {f1, _} = Float.parse(l1)
            {f5, _} = Float.parse(l5)
            {f15, _} = Float.parse(l15)
            %{load_1: f1, load_5: f5, load_15: f15}

          _ ->
            %{load_1: 0.0, load_5: 0.0, load_15: 0.0}
        end

      _ ->
        %{load_1: 0.0, load_5: 0.0, load_15: 0.0}
    end
  end

  @doc """
  Parses `free -m` output into memory metrics.
  """
  def parse_free(output) when is_binary(output) do
    lines =
      output
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)

    mem_line = Enum.find(lines, &String.starts_with?(&1, "Mem:"))
    buffers_cache_line = Enum.find(lines, &String.contains?(&1, "buffers/cache"))

    case mem_line do
      nil ->
        {:error, "unable to parse Mem line from free output"}

      line ->
        tokens =
          line
          |> String.split(~r/\s+/)
          |> Enum.drop(1)
          |> Enum.map(&parse_int/1)

        cond do
          buffers_cache_line != nil ->
            [total, used, free | _] = tokens

            avail =
              case Regex.run(~r/([\d]+)\s+([\d]+)$/, buffers_cache_line) do
                [_, _used_bc, free_bc] -> parse_int(free_bc)
                _ -> free
              end

            used_pct = Float.round((total - avail) / total * 100, 1)

            {:ok,
             %{
               total_mb: total,
               used_mb: used,
               free_mb: free,
               available_mb: avail,
               used_percent: used_pct
             }}

          match?([_, _, _, _, _, _ | _], tokens) ->
            [total, used, free, _shared, _buff_cache, available | _] = tokens
            used_pct = Float.round((total - available) / total * 100, 1)

            {:ok,
             %{
               total_mb: total,
               used_mb: used,
               free_mb: free,
               available_mb: available,
               used_percent: used_pct
             }}

          true ->
            {:error, "unexpected format in free output"}
        end
    end
  end

  @doc """
  Parses `df -h` or `df -h -P` output into disk metrics.
  """
  def parse_df(output) when is_binary(output) do
    lines =
      output
      |> String.split(~r/\r?\n/)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    disk_entries =
      lines
      |> Enum.drop(1)
      |> Enum.map(&parse_df_line/1)
      |> Enum.reject(&is_nil/1)

    if Enum.empty?(disk_entries) do
      {:error, "no valid filesystems found in df output"}
    else
      root_disk =
        Enum.find(disk_entries, fn d -> d.mount == "/" end) ||
          List.first(disk_entries)

      {:ok, %{disks: disk_entries, root: root_disk}}
    end
  end

  defp parse_df_line(line) do
    case String.split(line, ~r/\s+/) do
      [fs, size, used, avail, pct_str, mount | _] ->
        pct =
          pct_str
          |> String.replace("%", "")
          |> parse_int()

        %{
          filesystem: fs,
          size: size,
          used: used,
          avail: avail,
          use_percent: pct,
          mount: mount
        }

      _ ->
        nil
    end
  end

  defp parse_int(str) do
    case Integer.parse(str) do
      {int, _} -> int
      _ -> 0
    end
  end
end
