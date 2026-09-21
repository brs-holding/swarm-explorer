defmodule ZcashExplorerWeb.RecentBlocksLive do
  @moduledoc """
  The "Latest blocks" list of the Swarm Style Guide explorer screen: height,
  hash, transaction count, age, and a per-block shielded-share bar.

  SWARM change: the shielded share is computed in the block warmer from this
  block's own transactions (see `ZcashExplorerWeb.BlockView.shielded_share/1`),
  not taken from a design placeholder. A block that holds nothing but its
  coinbase has no honest share to show and renders an em dash.
  """
  use ZcashExplorerWeb, :live_view
  alias ZcashExplorerWeb.BlockView

  @refresh 5_000

  @impl true
  def render(assigns) do
    ~L"""
    <div class="sw-card overflow-hidden">
      <div class="flex items-center justify-between px-5 py-4" style="border-bottom:1px solid var(--sw-hairline);">
        <h3 class="font-display text-sm font-semibold">Latest blocks</h3>
        <span class="sw-mono text-[10.5px] tracking-[.14em]" style="color:var(--sw-honey);">
          <span class="sw-live-dot inline-block align-middle mr-2"></span>LIVE
        </span>
      </div>

      <%= if @block_cache == [] do %>
        <p class="px-5 py-6 text-sm" style="color:var(--sw-mid);">Waiting for the node&hellip;</p>
      <% end %>

      <%= for block <- @block_cache do %>
        <a href="<%= "/blocks/#{block["height"]}" %>"
           class="flex items-center gap-4 px-5 py-3 no-underline"
           style="border-bottom:1px solid var(--sw-hairline-soft);">
          <svg width="30" height="30" viewBox="0 0 24 24" fill="none" aria-hidden="true">
            <path d="M12 3 19.8 7.5 19.8 16.5 12 21 4.2 16.5 4.2 7.5Z" fill="rgba(255,138,31,.12)" stroke="#7d746a" stroke-width="1.4"/>
            <path d="M12 12 19.8 7.5M12 12v9M12 12 4.2 7.5" stroke="#7d746a" stroke-width="1" opacity=".6"/>
          </svg>

          <span class="flex-1 min-w-0">
            <span class="block sw-mono text-[13px]" style="color:var(--sw-text);">#<%= block["height"] %></span>
            <span class="block sw-mono text-[10.5px] truncate" style="color:var(--sw-dim);"><%= block["hash"] %></span>
          </span>

          <span class="text-right">
            <span class="block text-[12.5px]" style="color:var(--sw-text2);"><%= block["tx_count"] %> txs</span>
            <span class="block sw-mono text-[10.5px]" style="color:var(--sw-dim);"><%= block["time"] %></span>
          </span>

          <span class="w-16 shrink-0"
                title="Share of this block's non-coinbase transactions that carry at least one shielded component. Blocks with only a coinbase show no share.">
            <span class="sw-shield-bar block">
              <span style="width: <%= BlockView.shielded_share_width(block["shielded_share"]) %>%"></span>
            </span>
            <span class="block sw-mono text-[9.5px] text-right mt-1" style="color:var(--sw-dim);">
              <%= BlockView.shielded_share_label(block["shielded_share"]) %> &#11042;
            </span>
          </span>
        </a>
      <% end %>
    </div>
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Process.send_after(self(), :update, @refresh)
    {:ok, assign(socket, block_cache: ZcashExplorer.Cache.get("block_cache", []))}
  end

  @impl true
  def handle_info(:update, socket) do
    Process.send_after(self(), :update, @refresh)
    {:noreply, assign(socket, :block_cache, ZcashExplorer.Cache.get("block_cache", []))}
  end
end
