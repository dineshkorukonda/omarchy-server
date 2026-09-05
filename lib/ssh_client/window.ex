defmodule SSHClient.Window do
  @moduledoc """
  Desktop window management using `elixir-desktop` / WebView2 (Windows) & WebKitGTK (Linux).
  """

  @doc """
  Launches the desktop window pointing to the local LiveView endpoint.
  """
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent
    }
  end

  def start_link(opts \\ []) do
    title = Keyword.get(opts, :title, "ssh-client")
    url = Keyword.get(opts, :url, "http://localhost:4000")
    size = Keyword.get(opts, :size, {1024, 720})

    if Code.ensure_loaded?(Desktop.Window) do
      apply(Desktop.Window, :start_link, [
        [
          app: :ssh_client,
          id: SSHClientWindow,
          title: title,
          size: size,
          url: url
        ]
      ])
    else
      # Fallback when running headless or in test mode
      Task.start_link(fn -> Process.sleep(:infinity) end)
    end
  end
end
