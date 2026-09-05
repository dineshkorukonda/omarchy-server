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
  """
  @spec send_notification(String.t(), String.t(), String.t()) :: :ok
  def send_notification(urgency, summary, body) do
    case System.find_executable("notify-send") do
      nil ->
        :ok

      notify_send ->
        Task.start(fn ->
          System.cmd(notify_send, ["-u", urgency, "-a", "omarchy-server", summary, body],
            stderr_to_stdout: true
          )
        end)

        :ok
    end
  end

  # Maps a state transition to a notification or :skip.
  defp classify_transition(:connecting, :reconnecting), do: :skip
  defp classify_transition(:reconnecting, :reconnecting), do: :skip

  defp classify_transition(_old, :reconnecting) do
    {:notify, "critical", "omarchy-server: server offline",
     "A monitored server is unreachable and reconnecting."}
  end

  defp classify_transition(:reconnecting, :polling) do
    {:notify, "normal", "omarchy-server: server recovered",
     "A monitored server is back online and polling."}
  end

  defp classify_transition(:polling, :degraded) do
    {:notify, "normal", "omarchy-server: server degraded",
     "A monitored server has entered a degraded state."}
  end

  defp classify_transition(:degraded, :polling) do
    {:notify, "low", "omarchy-server: server recovered",
     "A monitored server has recovered from degraded state."}
  end

  defp classify_transition(_old, _new), do: :skip
end
