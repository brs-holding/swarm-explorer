defmodule ZcashExplorerWeb.HalvingLive do
  @moduledoc """
  The height of the next halving and the number of blocks to go.

  New in the SWARM fork. The interval is configuration (`SWARM_HALVING_INTERVAL`,
  default 1,680,000), which puts the first halving at height 1,679,999 — see
  `specs/ECONOMICS.md` §3.
  """
  use ZcashExplorerWeb, :live_view
  alias ZcashExplorer.Swarm

  @refresh 15_000

  @impl true
  def render(assigns) do
    ~L"""
    <p class="text-2xl font-semibold text-gray-900 dark:text-slate-100">
      <%= @next_halving %>
    </p>
    <p class="text-xs text-gray-500 dark:text-gray-400">
      <%= @remaining %> blocks to go
    </p>
    """
  end

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
    case ZcashExplorer.Cache.field("metrics", "blocks") do
      height when is_integer(height) ->
        [
          next_halving: Swarm.next_halving_height(height),
          remaining: Swarm.blocks_to_halving(height)
        ]

      _ ->
        [next_halving: "loading...", remaining: "-"]
    end
  end
end
