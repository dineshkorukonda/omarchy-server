defmodule SSHClientTest do
  use ExUnit.Case
  doctest SSHClient

  test "greets the world" do
    assert SSHClient.hello() == :world
  end

  test "supervisor boots and dynamic supervisor starts with no children" do
    assert Process.whereis(SSHClient.Supervisor) != nil
    assert Process.whereis(SSHClient.ServerSupervisor) != nil
    assert DynamicSupervisor.which_children(SSHClient.ServerSupervisor) == []
  end
end
