defmodule OmarchyServer.TerminalSupervisor do
  @moduledoc """
  DynamicSupervisor managing active PTY terminal sessions.
  """

  use DynamicSupervisor

  @name __MODULE__

  def start_link(init_arg \\ []) do
    DynamicSupervisor.start_link(__MODULE__, init_arg, name: @name)
  end

  @impl true
  def init(_init_arg) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Starts a new PTY session child under supervision.
  """
  def start_session(server, opts \\ []) do
    spec = {OmarchyServer.SSH.PTYSession, {server, opts}}
    DynamicSupervisor.start_child(@name, spec)
  end

  @doc """
  Stops an active PTY session child.
  """
  def stop_session(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(@name, pid)
  end
end
