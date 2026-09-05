defmodule SSHClientWeb.CoreComponents do
  @moduledoc """
  Provides core UI components used throughout the application.
  """

  use Phoenix.Component

  @doc "Status badge component"
  attr :status, :string, required: true

  def status_badge(assigns) do
    ~H"""
    <span class={[
      "inline-flex items-center px-2 py-0.5 rounded text-xs font-medium font-mono tracking-wide",
      badge_class(@status)
    ]}>
      <%= @status %>
    </span>
    """
  end

  defp badge_class("polling"), do: "bg-emerald-500/10 text-emerald-400 border border-emerald-500/20"
  defp badge_class("connecting"), do: "bg-blue-500/10 text-blue-400 border border-blue-500/20"
  defp badge_class("degraded"), do: "bg-amber-500/10 text-amber-400 border border-amber-500/20"
  defp badge_class("reconnecting"), do: "bg-purple-500/10 text-purple-400 border border-purple-500/20"
  defp badge_class(_), do: "bg-zinc-500/10 text-zinc-400 border border-zinc-500/20"

  @doc "Metric bar component"
  attr :label, :string, required: true
  attr :value, :float, default: 0.0

  def metric_bar(assigns) do
    ~H"""
    <div class="flex items-center gap-2">
      <span class="text-[11px] text-zinc-500 w-8 font-mono"><%= @label %></span>
      <div class="flex-1 h-1 bg-zinc-800 rounded-full overflow-hidden">
        <div
          class={["h-full rounded-full transition-all duration-500", bar_color(@value)]}
          style={"width: #{min(@value, 100)}%"}
        />
      </div>
      <span class="text-[11px] text-zinc-400 w-10 text-right font-mono">
        <%= :erlang.float_to_binary(@value + 0.0, decimals: 1) %>%
      </span>
    </div>
    """
  end

  defp bar_color(v) when v >= 90, do: "bg-red-500"
  defp bar_color(v) when v >= 70, do: "bg-amber-500"
  defp bar_color(_), do: "bg-blue-500"
end
