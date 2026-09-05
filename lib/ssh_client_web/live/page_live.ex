defmodule SSHClientWeb.PageLive do
  @moduledoc """
  Minimal hello / status LiveView page for desktop shell bootstrap.
  """

  def detect_os do
    case :os.type() do
      {:win32, _} -> "Windows (WebView2)"
      {:unix, :darwin} -> "macOS (WebKit)"
      {:unix, _} -> "Linux (WebKitGTK)"
      _ -> "Unknown"
    end
  end

  def initial_state do
    %{
      page_title: "ssh-client",
      app_status: :ready,
      platform: detect_os(),
      version: "0.2.0"
    }
  end
end
