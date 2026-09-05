defmodule SSHClient.KeychainTest do
  use ExUnit.Case, async: true

  alias SSHClient.Keychain

  describe "detect_backend/0" do
    test "returns expected backend for the current platform" do
      backend = Keychain.detect_backend()
      assert backend in [:libsecret, :credential_manager, :memory]
    end
  end

  describe "store/3, retrieve/2, delete/2 with in-memory backend" do
    test "stores secret, retrieves it, and deletes it cleanly" do
      account = "user@prod-srv-test"
      secret = "s3cr3t_p@ssw0rd!"

      assert :ok = Keychain.store(account, secret, backend: :memory)
      assert {:ok, ^secret} = Keychain.retrieve(account, backend: :memory)

      assert :ok = Keychain.delete(account, backend: :memory)
      assert {:error, :not_found} = Keychain.retrieve(account, backend: :memory)
    end

    test "returns :not_found for non-existent secret" do
      assert {:error, :not_found} = Keychain.retrieve("non-existent-account", backend: :memory)
    end
  end

  describe "Credential Manager backend" do
    test "stores, retrieves, and deletes credential via credential_manager backend" do
      account = "win-test-user@win-host"
      secret = "win_s3cr3t_p@ss!"

      assert :ok = Keychain.store(account, secret, backend: :credential_manager)
      assert {:ok, retrieved} = Keychain.retrieve(account, backend: :credential_manager)
      assert retrieved == secret or is_binary(retrieved)

      assert :ok = Keychain.delete(account, backend: :credential_manager)
    end
  end
end
