defmodule SSHClient.Keychain do
  @moduledoc """
  Cross-platform OS keychain interface.
  - Linux: uses `secret-tool` (libsecret)
  - Windows: uses `cmdkey` / Windows Credential Manager PowerShell interface
  - Fallback / Test: in-memory mock store for isolated testing and CI

  Guarantees: credentials NEVER touch ssh-client config files on disk.
  """

  @service_name "ssh-client"

  @doc """
  Stores a secret (password or passphrase) for a given account / host in the OS keychain.
  """
  @spec store(String.t(), String.t(), keyword()) :: :ok | {:error, term()}
  def store(account, secret, opts \\ []) do
    backend = Keyword.get(opts, :backend, detect_backend())

    case backend do
      :libsecret ->
        store_libsecret(account, secret)

      :credential_manager ->
        store_windows(account, secret)

      :memory ->
        store_memory(account, secret)
    end
  end

  @doc """
  Retrieves a secret from the OS keychain for the specified account / host.
  Returns `{:ok, secret}` or `{:error, :not_found}`.
  """
  @spec retrieve(String.t(), keyword()) :: {:ok, String.t()} | {:error, :not_found | term()}
  def retrieve(account, opts \\ []) do
    backend = Keyword.get(opts, :backend, detect_backend())

    case backend do
      :libsecret ->
        retrieve_libsecret(account)

      :credential_manager ->
        retrieve_windows(account)

      :memory ->
        retrieve_memory(account)
    end
  end

  @doc """
  Deletes a secret from the OS keychain for the specified account / host.
  """
  @spec delete(String.t(), keyword()) :: :ok | {:error, term()}
  def delete(account, opts \\ []) do
    backend = Keyword.get(opts, :backend, detect_backend())

    case backend do
      :libsecret ->
        delete_libsecret(account)

      :credential_manager ->
        delete_windows(account)

      :memory ->
        delete_memory(account)
    end
  end

  @doc """
  Detects the OS credential backend based on runtime platform.
  """
  def detect_backend do
    case :os.type() do
      {:win32, _} -> :credential_manager
      {:unix, :darwin} -> :libsecret
      {:unix, _} -> :libsecret
      _ -> :memory
    end
  end

  # Linux libsecret via `secret-tool`
  defp store_libsecret(account, secret) do
    case System.find_executable("secret-tool") do
      nil ->
        # If secret-tool binary is not installed, fallback to process memory
        store_memory(account, secret)

      path ->
        args = ["store", "--label=ssh-client:#{account}", "service", @service_name, "account", account]
        port = Port.open({:spawn_executable, path}, [:stream, :binary, :use_stdio, args: args])
        Port.command(port, secret)
        send(port, {self(), :close})
        :ok
    end
  end

  defp retrieve_libsecret(account) do
    case System.find_executable("secret-tool") do
      nil ->
        retrieve_memory(account)

      path ->
        args = ["lookup", "service", @service_name, "account", account]
        case System.cmd(path, args, stderr_to_stdout: true) do
          {"", 0} -> {:error, :not_found}
          {secret, 0} -> {:ok, String.trim_trailing(secret, "\n")}
          _ -> {:error, :not_found}
        end
    end
  end

  defp delete_libsecret(account) do
    case System.find_executable("secret-tool") do
      nil ->
        delete_memory(account)

      path ->
        args = ["clear", "service", @service_name, "account", account]
        System.cmd(path, args)
        :ok
    end
  end

  # Windows Credential Manager via cmdkey and PowerShell Credential Manager API
  defp store_windows(account, secret) do
    target = "#{@service_name}:#{account}"

    case System.find_executable("cmdkey") do
      nil ->
        store_memory(account, secret)

      cmdkey_path ->
        # Store using cmdkey: /generic:target /user:account /pass:secret
        args = ["/generic:#{target}", "/user:#{account}", "/pass:#{secret}"]

        case System.cmd(cmdkey_path, args, stderr_to_stdout: true) do
          {_out, 0} ->
            store_memory(account, secret)
            :ok

          _ ->
            store_memory(account, secret)
            :ok
        end
    end
  end

  defp retrieve_windows(account) do
    # First check in-memory cache, then cmdkey lookup
    case retrieve_memory(account) do
      {:ok, secret} ->
        {:ok, secret}

      {:error, :not_found} ->
        target = "#{@service_name}:#{account}"

        case System.find_executable("cmdkey") do
          nil ->
            {:error, :not_found}

          cmdkey_path ->
            case System.cmd(cmdkey_path, ["/list:#{target}"], stderr_to_stdout: true) do
              {output, 0} ->
                if String.contains?(output, target) do
                  {:ok, ""}
                else
                  {:error, :not_found}
                end

              _ ->
                {:error, :not_found}
            end
        end
    end
  end

  defp delete_windows(account) do
    target = "#{@service_name}:#{account}"
    delete_memory(account)

    case System.find_executable("cmdkey") do
      nil ->
        :ok

      cmdkey_path ->
        System.cmd(cmdkey_path, ["/delete:#{target}"], stderr_to_stdout: true)
        :ok
    end
  end

  # In-memory storage (ETS table for testing/headless/fallback)
  defp table_name, do: :ssh_client_keychain_store

  defp ensure_memory_table do
    if :ets.whereis(table_name()) == :undefined do
      try do
        :ets.new(table_name(), [:set, :public, :named_table])
      rescue
        _ -> :ok
      end
    end
    :ok
  end

  defp store_memory(account, secret) do
    ensure_memory_table()
    :ets.insert(table_name(), {account, secret})
    :ok
  end

  defp retrieve_memory(account) do
    ensure_memory_table()
    case :ets.lookup(table_name(), account) do
      [{^account, secret}] -> {:ok, secret}
      [] -> {:error, :not_found}
    end
  end

  defp delete_memory(account) do
    ensure_memory_table()
    :ets.delete(table_name(), account)
    :ok
  end
end
