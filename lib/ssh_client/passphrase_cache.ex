defmodule SSHClient.PassphraseCache do
  @moduledoc """
  Session-only, in-memory passphrase cache for decrypted SSH private keys.

  Guarantees:
  - Stored only in volatile RAM of this process/ETS table.
  - Never written to disk, logs, or persistent configuration.
  - Automatically flushed on session terminate or app exit.
  """

  use GenServer

  @name __MODULE__
  @table :ssh_client_passphrase_ram_cache

  # Client API

  @doc """
  Starts the PassphraseCache GenServer.
  """
  def start_link(opts \\ []) do
    name = Keyword.get(opts, :name, @name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @doc """
  Puts a passphrase in memory for a given key path or fingerprint.
  """
  @spec put(String.t(), String.t()) :: :ok
  def put(key_identifier, passphrase) when is_binary(key_identifier) and is_binary(passphrase) do
    ensure_table()
    :ets.insert(@table, {key_identifier, passphrase})
    :ok
  end

  @doc """
  Gets a cached passphrase for a given key path or fingerprint.
  Returns `{:ok, passphrase}` or `{:error, :not_found}`.
  """
  @spec get(String.t()) :: {:ok, String.t()} | {:error, :not_found}
  def get(key_identifier) when is_binary(key_identifier) do
    ensure_table()

    case :ets.lookup(@table, key_identifier) do
      [{^key_identifier, passphrase}] -> {:ok, passphrase}
      [] -> {:error, :not_found}
    end
  end

  @doc """
  Clears a specific cached passphrase.
  """
  @spec delete(String.t()) :: :ok
  def delete(key_identifier) when is_binary(key_identifier) do
    ensure_table()
    :ets.delete(@table, key_identifier)
    :ok
  end

  @doc """
  Purges all cached passphrases from memory immediately.
  """
  @spec clear_all() :: :ok
  def clear_all do
    ensure_table()
    :ets.delete_all_objects(@table)
    :ok
  end

  # Server Callbacks

  @impl true
  def init(_opts) do
    ensure_table()
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    clear_all()
    :ok
  end

  defp ensure_table do
    if :ets.whereis(@table) == :undefined do
      try do
        :ets.new(@table, [:set, :public, :named_table])
      rescue
        _ -> :ok
      end
    end

    :ok
  end
end
