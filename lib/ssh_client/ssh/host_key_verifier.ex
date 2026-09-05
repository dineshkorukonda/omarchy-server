defmodule SSHClient.SSH.HostKeyVerifier do
  @moduledoc """
  Verifies remote SSH host keys against `known_hosts`, generates SHA256 fingerprints,
  detects first-connect and fingerprint diffs on host key changes, and persists
  accepted host keys.
  """

  @default_known_hosts "~/.ssh/known_hosts"

  @type verification_result ::
          {:ok, :trusted, %{fingerprint: String.t()}}
          | {:error,
             {:first_connect,
              %{host: String.t(), port: pos_integer(), fingerprint: String.t(), key: term()}}}
          | {:error,
             {:host_key_changed,
              %{
                host: String.t(),
                port: pos_integer(),
                old_fingerprint: String.t(),
                new_fingerprint: String.t(),
                key: term()
              }}}

  @doc """
  Computes standard OpenSSH SHA256 fingerprint for a public key.
  Returns string format: "SHA256:Base64HashWithoutPadding"
  """
  @spec fingerprint(term()) :: String.t()
  def fingerprint(key) do
    encoded = encode_public_key(key)
    hash = :crypto.hash(:sha256, encoded)
    "SHA256:" <> Base.encode64(hash, padding: false)
  end

  @doc """
  Encodes an Erlang public key record or binary into wire format.
  """
  @spec encode_public_key(term()) :: binary()
  def encode_public_key(key) when is_binary(key), do: key

  def encode_public_key(key) do
    try do
      :ssh_message.ssh2_pubkey_encode(key)
    catch
      _, _ ->
        try do
          :ssh_file.encode([key], :public_key)
        catch
          _, _ -> :erlang.term_to_binary(key)
        end
    end
  end

  @doc """
  Resolves the absolute path to known_hosts file.
  """
  @spec known_hosts_path(keyword()) :: Path.t()
  def known_hosts_path(opts \\ []) do
    path =
      Keyword.get(opts, :known_hosts_file) ||
        case Keyword.get(opts, :user_dir) do
          nil -> @default_known_hosts
          dir -> Path.join(to_string(dir), "known_hosts")
        end

    Path.expand(path)
  end

  @doc """
  Reads and parses all known_hosts entries from file.
  Returns list of %{host_pattern: String.t(), key: term(), raw: String.t()}
  """
  @spec load_known_hosts(keyword()) :: list(map())
  def load_known_hosts(opts \\ []) do
    path = known_hosts_path(opts)

    if File.exists?(path) do
      path
      |> File.read!()
      |> String.split("\n", trim: true)
      |> Enum.reject(&String.starts_with?(&1, "#"))
      |> Enum.map(&parse_known_host_line/1)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp parse_known_host_line(line) do
    parts = String.split(line, " ", trim: true)

    case parts do
      [hosts, type, b64_key | _rest] ->
        case Base.decode64(b64_key) do
          {:ok, raw_key} ->
            %{
              hosts: String.split(hosts, ","),
              type: type,
              key: raw_key,
              fingerprint: fingerprint(raw_key),
              raw: line
            }

          _ ->
            nil
        end

      _ ->
        nil
    end
  end

  @doc """
  Verifies a host key against known_hosts.
  Returns:
  - `{:ok, :trusted, %{fingerprint: fp}}` if key matches
  - `{:error, {:first_connect, %{host: host, port: port, fingerprint: fp, key: key}}}` if no entry exists
  - `{:error, {:host_key_changed, %{host: host, port: port, old_fingerprint: old_fp, new_fingerprint: fp, key: key}}}` if mismatched
  """
  @spec verify(term(), String.t(), pos_integer(), keyword()) :: verification_result()
  def verify(key, host, port, opts \\ []) do
    target_host = to_string(host)
    entries = load_known_hosts(opts)
    new_fp = fingerprint(key)

    matching_host_entries =
      Enum.filter(entries, fn entry ->
        host_matches?(entry.hosts, target_host, port)
      end)

    case matching_host_entries do
      [] ->
        {:error,
         {:first_connect, %{host: target_host, port: port, fingerprint: new_fp, key: key}}}

      existing_entries ->
        exact_match =
          Enum.find(existing_entries, fn entry ->
            entry.fingerprint == new_fp
          end)

        if exact_match do
          {:ok, :trusted, %{fingerprint: new_fp}}
        else
          old_fp = hd(existing_entries).fingerprint

          {:error,
           {:host_key_changed,
            %{
              host: target_host,
              port: port,
              old_fingerprint: old_fp,
              new_fingerprint: new_fp,
              key: key
            }}}
        end
    end
  end

  defp host_matches?(patterns, host, port) do
    expected_host_port =
      if port == 22 do
        host
      else
        "[#{host}]:#{port}"
      end

    Enum.any?(patterns, fn pattern ->
      pattern == host or pattern == expected_host_port or pattern == "[#{host}]:#{port}"
    end)
  end

  @doc """
  Saves an accepted host key into known_hosts.
  """
  @spec save_host_key(String.t(), pos_integer(), term(), keyword()) :: :ok | {:error, term()}
  def save_host_key(host, port, key, opts \\ []) do
    path = known_hosts_path(opts)
    dir = Path.dirname(path)
    File.mkdir_p!(dir)

    target_host = to_string(host)

    host_token =
      if port == 22 do
        target_host
      else
        "[#{target_host}]:#{port}"
      end

    encoded_key = encode_public_key(key)
    b64_key = Base.encode64(encoded_key)

    key_type =
      cond do
        is_tuple(key) -> to_string(elem(key, 0))
        true -> "ssh-ed25519"
      end

    line = "#{host_token} #{key_type} #{b64_key}\n"

    case File.write(path, line, [:append]) do
      :ok -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Replaces or updates a host key entry in known_hosts after explicit confirmation.
  """
  @spec update_host_key(String.t(), pos_integer(), term(), keyword()) :: :ok | {:error, term()}
  def update_host_key(host, port, key, opts \\ []) do
    path = known_hosts_path(opts)
    target_host = to_string(host)

    if File.exists?(path) do
      filtered_lines =
        path
        |> File.read!()
        |> String.split("\n", trim: true)
        |> Enum.reject(fn line ->
          case parse_known_host_line(line) do
            nil -> false
            entry -> host_matches?(entry.hosts, target_host, port)
          end
        end)

      File.write!(
        path,
        Enum.join(filtered_lines, "\n") <> if(filtered_lines == [], do: "", else: "\n")
      )
    end

    save_host_key(host, port, key, opts)
  end
end
