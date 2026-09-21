defmodule ZcashExplorerWeb.ShieldedPoolLive do
  @moduledoc """
  Every value pool the node reports, as one card.

  SWARM change: was `OrchardPoolLive`, which showed the Orchard pool only and
  labelled it ZEC/TAZ. SwarmTestnet activates every upgrade through NU6.3 at
  height 1, so Sapling, Orchard and the NU6.3 Ironwood pool can all hold value.
  The list comes from `getblockchaininfo`, so a pool added later appears with no
  code change and none is invented when the node reports none.
  """
  use ZcashExplorerWeb, :live_view
  alias ZcashExplorer.Swarm

  @refresh 15_000

  @impl true
  def render(assigns) do
    ~L"""
    <div class="sw-card px-5 py-4">
      <div class="flex items-baseline justify-between">
        <span class="sw-key">SHIELDED VALUE POOLS</span>
        <span class="sw-mono text-[10.5px]" style="color:var(--sw-low);">from getblockchaininfo</span>
      </div>

      <%= if @pools == [] do %>
        <p class="mt-3 text-sm" style="color:var(--sw-mid);">The node reports no value pools yet.</p>
      <% else %>
        <div class="mt-3 flex flex-wrap gap-2.5">
          <%= for {id, value} <- @pools do %>
            <span class="sw-pill sw-pill-shielded">
              <span class="capitalize" style="letter-spacing:0;"><%= id %></span>
              <span class="sw-mono"><%= value %> <%= @ticker %></span>
            </span>
          <% end %>
        </div>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :update, @refresh)
    {:ok, assign(socket, pools: pools(), ticker: Swarm.ticker())}
  end

  @impl true
  def handle_info(:update, socket) do
    Process.send_after(self(), :update, @refresh)
    {:noreply, assign(socket, :pools, pools())}
  end

  defp pools do
    ZcashExplorer.Cache.get("metrics", %{})
    |> Map.get("valuePools")
    |> Swarm.shielded_pools()
  end
end
