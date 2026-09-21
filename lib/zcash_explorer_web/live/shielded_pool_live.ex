defmodule ZcashExplorerWeb.ShieldedPoolLive do
  @moduledoc """
  Every shielded value pool the node reports.

  SWARM change: was `OrchardPoolLive`, which showed the Orchard pool only and
  labelled it ZEC/TAZ. SwarmTestnet activates every upgrade through NU6.3 at
  height 1, so Sapling, Orchard and the NU6.3 Ironwood pool can all hold value.
  The list comes from `getblockchaininfo`, so a pool added later shows up with
  no code change.
  """
  use ZcashExplorerWeb, :live_view
  alias ZcashExplorer.Swarm

  @refresh 15_000

  @impl true
  def render(assigns) do
    ~L"""
    <div class="space-y-1">
      <%= if @pools == [] do %>
        <p class="text-2xl font-semibold text-gray-900 dark:text-slate-100">&mdash;</p>
      <% else %>
        <%= for {id, value} <- @pools do %>
          <p class="text-sm text-gray-500 dark:text-gray-400">
            <span class="capitalize"><%= id %></span>
            <span class="font-semibold text-gray-900 dark:text-slate-100"><%= value %></span>
            <%= @ticker %>
          </p>
        <% end %>
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
