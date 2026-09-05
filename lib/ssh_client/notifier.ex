defmodule SSHClient.Notifier do
  @moduledoc """
  Sends desktop notifications when a server changes state.

  Delegates to notify-send on Linux. When notify-send is unavailable the
  notification is silently skipped so the daemon does not crash on headless
  systems.

  Call `notify_state_change/3` when a ServerWorker transitions between states.
  Only transitions that cross a severity boundary emit a notification:
    - any state -> :reconnecting  (server went offline)
    - :reconnecting -> :polling   (server recovered)
    - :polling -> :degraded       (server degraded)
    - :degraded -> :polling       (server recovered from degraded state)
  """

  @doc """
  Fires a desktop notification if the state transition is noteworthy.
  Returns :ok regardless of whether notify-send is installed.
  """
  @spec notify_state_change(String.t(), atom(), atom()) :: :ok
  def notify_state_change(server_name, old_state, new_state) do
    case classify_transition(old_state, new_state) do
      {:notify, urgency, summary, body} ->
        send_notification(urgency, summary, "#{server_name}: #{body}")

      :skip ->
        :ok
    end
  end

  @doc """
  Sends a raw desktop notification with the given urgency, summary, and body.
  Urgency is one of: "low", "normal", "critical".

  Dispatches via:
  1. Desktop.Notification (if elixir-desktop is loaded in GUI mode)
  2. Windows native PowerShell BurntToast or balloon tooltip
  3. Linux notify-send
  4. Silent fallback in headless/test environments
  """
  @spec send_notification(String.t(), String.t(), String.t()) :: :ok
  def send_notification(urgency, summary, body) do
    cond do
      Code.ensure_loaded?(Desktop.Notification) ->
        try do
          apply(Desktop.Notification, :show, [
            [
              title: summary,
              content: body,
              app: :ssh_client
            ]
          ])
        rescue
          _ -> fallback_os_notification(urgency, summary, body)
        catch
          _, _ -> fallback_os_notification(urgency, summary, body)
        end

        :ok

      true ->
        fallback_os_notification(urgency, summary, body)
    end
  end

  defp fallback_os_notification(urgency, summary, body) do
    case :os.type() do
      {:win32, _} ->
        send_windows_notification(summary, body)

      _ ->
        send_linux_notification(urgency, summary, body)
    end
  end

  defp send_linux_notification(urgency, summary, body) do
    case System.find_executable("notify-send") do
      nil ->
        :ok

      notify_send ->
        Task.start(fn ->
          System.cmd(notify_send, ["-u", urgency, "-a", "ssh-client", summary, body],
            stderr_to_stdout: true
          )
        end)

        :ok
    end
  end

  defp send_windows_notification(summary, body) do
    case System.find_executable("powershell") || System.find_executable("pwsh") do
      nil ->
        :ok

      ps_exe ->
        # PowerShell toast or BalloonTip notification
        escaped_summary = String.replace(summary, "'", "''")
        escaped_body = String.replace(body, "'", "''")

        ps_script =
          "[reflection.assembly]::loadwithpartialname('System.Windows.Forms') | Out-Null; " <>
            "[reflection.assembly]::loadwithpartialname('System.Drawing') | Out-Null; " <>
            "$notify = new-object system.windows.forms.notifyicon; " <>
            "$notify.icon = [system.drawing.systemicons]::Information; " <>
            "$notify.visible = $true; " <>
            "$notify.showballoontip(3000, '#{escaped_summary}', '#{escaped_body}', [system.windows.forms.tooltipicon]::Info)"

        Task.start(fn ->
          System.cmd(ps_exe, ["-NoProfile", "-Command", ps_script], stderr_to_stdout: true)
        end)

        :ok
    end
  end

  # Maps a state transition to a notification or :skip.
  defp classify_transition(:connecting, :reconnecting), do: :skip
  defp classify_transition(:reconnecting, :reconnecting), do: :skip

  defp classify_transition(_old, :reconnecting) do
    {:notify, "critical", "ssh-client: server offline",
     "A monitored server is unreachable and reconnecting."}
  end

  defp classify_transition(:reconnecting, :polling) do
    {:notify, "normal", "ssh-client: server recovered",
     "A monitored server is back online and polling."}
  end

  defp classify_transition(:polling, :degraded) do
    {:notify, "normal", "ssh-client: server degraded",
     "A monitored server has entered a degraded state."}
  end

  defp classify_transition(:degraded, :polling) do
    {:notify, "low", "ssh-client: server recovered",
     "A monitored server has recovered from degraded state."}
  end

  defp classify_transition(_old, _new), do: :skip
end
