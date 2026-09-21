defmodule ZcashExplorerWeb.RecentTransactionsLive do
  @moduledoc """
  The "Latest transactions" list, with the style guide's state pills.

  SWARM change: an amount is only printed when it is genuinely public. A
  shielded transaction shows the masked glyphs, because the chain does not
  contain a public amount for it and printing its transparent total would say
  something untrue about what was sent.
  """
  use ZcashExplorerWeb, :live_view
  alias ZcashExplorer.Swarm

  @refresh 5_000

  @impl true
  def render(assigns) do
    ~L"""
    <div class="sw-card overflow-hidden">
      <div class="flex items-center justify-between px-5 py-4" style="border-bottom:1px solid var(--sw-hairline);">
        <h3 class="font-display text-sm font-semibold">Latest transactions</h3>
        <span class="sw-mono text-[10.5px] tracking-[.14em]" style="color:var(--sw-honey);">
          <span class="sw-live-dot inline-block align-middle mr-2"></span>LIVE
        </span>
      </div>

      <%= if @transaction_cache == [] do %>
        <p class="px-5 py-6 text-sm" style="color:var(--sw-mid);">Waiting for the node&hellip;</p>
      <% end %>

      <%= for tx <- @transaction_cache do %>
        <a href="<%= "/transactions/#{tx["txid"]}" %>"
           class="flex items-center gap-3 px-5 py-3 no-underline"
           style="border-bottom:1px solid var(--sw-hairline-soft);">
          <span class="flex-1 min-w-0">
            <span class="block sw-mono text-[11.5px] truncate" style="color:var(--sw-text2);"><%= tx["txid"] %></span>
            <span class="block sw-mono text-[10.5px]" style="color:var(--sw-dim);">
              block #<%= tx["block_height"] %> &middot; <%= tx["time"] %>
            </span>
          </span>

          <span class="sw-mono text-[11.5px] shrink-0 <%= if tx["masked"], do: "sw-masked" %>"
                style="<%= unless tx["masked"], do: "color:var(--sw-clear-lt);" %>">
            <%= tx["amount"] %><%= unless tx["masked"] do %> <%= @ticker %><% end %>
          </span>

          <span class="<%= tx["pill_class"] %> shrink-0"><%= tx["state"] %></span>
        </a>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :update, @refresh)
    {:ok, assign(socket, transaction_cache: txs(), ticker: Swarm.ticker())}
  end

  @impl true
  def handle_info(:update, socket) do
    Process.send_after(self(), :update, @refresh)
    {:noreply, assign(socket, :transaction_cache, txs())}
  end

  defp txs, do: ZcashExplorer.Cache.get("transaction_cache", [])
end
