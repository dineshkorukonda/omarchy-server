defmodule SSHClient.UpdaterTest do
  use ExUnit.Case, async: true

  alias SSHClient.Updater

  describe "current_version/0" do
    test "returns current semver version" do
      assert Updater.current_version() == "0.0.1"
    end
  end

  describe "version_greater?/2" do
    test "correctly compares semantic versions" do
      assert Updater.version_greater?("0.0.2", "0.0.1") == true
      assert Updater.version_greater?("1.0.0", "0.0.1") == true
      assert Updater.version_greater?("0.0.1", "0.0.1") == false
      assert Updater.version_greater?("0.0.1", "0.0.2") == false
    end
  end
end
