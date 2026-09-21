defmodule ZcashExplorerWeb.MempoolInfoLive do
  @moduledoc """
  Number of transactions this node is holding in its mempool.
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
    pending = ZcashExplorer.Cache.get("raw_mempool")

    [
      key: "MEMPOOL",
      value: if(is_list(pending), do: Integer.to_string(length(pending)), else: "—"),
      note: "transactions waiting at this node",
      accent: MetricCard.honey()
    ]
  end
end
