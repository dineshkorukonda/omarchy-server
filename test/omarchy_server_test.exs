defmodule OmarchyServerTest do
  use ExUnit.Case
  doctest OmarchyServer

  test "greets the world" do
    assert OmarchyServer.hello() == :world
  end

  test "supervisor boots with no children" do
    assert Process.whereis(OmarchyServer.Supervisor) != nil
    assert Supervisor.which_children(OmarchyServer.Supervisor) == []
  end
end
