defmodule ZcashExplorerWeb.PeersLive do
  @moduledoc """
  How many peers this node is connected to, from `getpeerinfo`.

  SWARM change: the design mockup had a "NODES / 61 countries" card. This
  explorer talks to exactly one node and cannot see the size of the network or
  where its members are, so that card would have been an invention. What can be
  said honestly is how many peers the node behind this explorer has, and that is
  what the label says.
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
    peers = ZcashExplorer.Cache.get("zcash_nodes")

    [
      key: "PEERS",
      value: if(is_list(peers), do: Integer.to_string(length(peers)), else: "—"),
      note: "peers of this node",
      accent: MetricCard.muted()
    ]
  end
end
