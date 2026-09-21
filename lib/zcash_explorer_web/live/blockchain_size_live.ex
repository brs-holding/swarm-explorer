defmodule ZcashExplorerWeb.BlockChainSizeLive do
  @moduledoc """
  Size of the chain on the node's disk, from `getblockchaininfo`.
  """
  use ZcashExplorerWeb, :live_view
  alias ZcashExplorerWeb.MetricCard

  @refresh 30_000

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
      key: "CHAIN ON DISK",
      value: format(ZcashExplorer.Cache.field("metrics", "size_on_disk")),
      note: "as this node stores it",
      accent: MetricCard.muted()
    ]
  end

  defp format(bytes) when is_number(bytes), do: Sizeable.filesize(bytes)
  defp format(_), do: "—"
end
