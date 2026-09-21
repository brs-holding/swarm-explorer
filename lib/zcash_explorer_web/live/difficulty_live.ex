defmodule ZcashExplorerWeb.DifficultyLive do
  @moduledoc """
  Current difficulty, from `getblockchaininfo`.
  """
  use ZcashExplorerWeb, :live_view
  alias ZcashExplorerWeb.MetricCard

  @refresh 15_000

  @impl true
  def render(assigns), do: MetricCard.card(assigns)

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :update, @refresh)
    {:ok, assign(socket, figures())}
  end

  @impl true
  def handle_info(:update, socket) do
    Process.send_after(self(), :update, @refresh)
    {:noreply, assign(socket, figures())}
  end

  defp figures do
    [
      key: "DIFFICULTY",
      value: format(ZcashExplorer.Cache.field("metrics", "difficulty")),
      note: "retargeted every block",
      accent: MetricCard.muted()
    ]
  end

  defp format(d) when is_number(d),
    do: :erlang.float_to_binary(d + 0.0, [:compact, {:decimals, 6}])

  defp format(_), do: "—"
end
