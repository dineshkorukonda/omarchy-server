defmodule OmarchyServerTest do
  use ExUnit.Case
  doctest OmarchyServer

  test "greets the world" do
    assert OmarchyServer.hello() == :world
  end

  test "supervisor boots and dynamic supervisor starts with no children" do
    assert Process.whereis(OmarchyServer.Supervisor) != nil
    assert Process.whereis(OmarchyServer.ServerSupervisor) != nil
    assert DynamicSupervisor.which_children(OmarchyServer.ServerSupervisor) == []
  end
end
