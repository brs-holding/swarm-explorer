defmodule ZcashExplorerWeb.SupplyLive do
  @moduledoc """
  Total supply issued so far against the maximum.

  New in the SWARM fork. `chainSupply.chainValue` from `getblockchaininfo` is
  what the node has actually issued; the maximum is configuration
  (`SWARM_MAX_SUPPLY`, default 20,999,987.3152 from `specs/ECONOMICS.md` §3).
  """
  use ZcashExplorerWeb, :live_view
  alias ZcashExplorer.Swarm

  @refresh 15_000

  @impl true
  def render(assigns) do
    ~L"""
    <p class="text-2xl font-semibold text-gray-900 dark:text-slate-100">
      <%= @issued %>
    </p>
    <p class="text-xs text-gray-500 dark:text-gray-400">
      of <%= @max %> <%= @ticker %> (<%= @percent %>%)
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
    issued =
      ZcashExplorer.Cache.get("metrics", %{})
      |> get_in(["chainSupply", "chainValue"])

    [
      issued: format(issued),
      max: format(Swarm.max_supply()),
      percent: if(is_number(issued), do: Float.round(Swarm.supply_percent(issued), 4), else: "-"),
      ticker: Swarm.ticker()
    ]
  end

  defp format(value) when is_number(value),
    do: :erlang.float_to_binary(value + 0.0, [:compact, {:decimals, 4}])

  defp format(_), do: "loading..."
end
