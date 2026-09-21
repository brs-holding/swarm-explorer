defmodule ZcashExplorerWeb.BlockCountLive do
  @moduledoc """
  Chain tip height, straight from `getblockchaininfo`.
  """
  use ZcashExplorerWeb, :live_view
  alias ZcashExplorerWeb.MetricCard

  @refresh 5_000

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
    height = ZcashExplorer.Cache.field("metrics", "blocks")

    [
      key: "BLOCK HEIGHT",
      value: format(height),
      note: "target #{ZcashExplorer.Swarm.block_target_seconds()}s per block",
      accent: MetricCard.honey()
    ]
  end

  defp format(n) when is_integer(n), do: Integer.to_string(n)
  defp format(_), do: "—"
end
