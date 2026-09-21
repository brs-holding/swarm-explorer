defmodule ZcashExplorerWeb.SupplyLive do
  @moduledoc """
  Total supply issued so far against the maximum.

  `chainSupply.chainValue` is what the node has actually issued; the maximum is
  configuration (`SWARM_MAX_SUPPLY`, default 20,999,987.3152 from
  `specs/ECONOMICS.md` §3).
  """
  use ZcashExplorerWeb, :live_view
  alias ZcashExplorerWeb.MetricCard

  @refresh 15_000

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
    issued = get_in(ZcashExplorer.Cache.get("metrics", %{}), ["chainSupply", "chainValue"])

    [
      key: "SUPPLY ISSUED",
      value: format(issued, 4),
      note: note(issued),
      accent: MetricCard.honey()
    ]
  end

  defp note(issued) when is_number(issued) do
    "of #{format(ZcashExplorer.Swarm.max_supply(), 4)} #{ZcashExplorer.Swarm.ticker()} · " <>
      format(ZcashExplorer.Swarm.supply_percent(issued), 3) <> "%"
  end

  defp note(_), do: "of #{format(ZcashExplorer.Swarm.max_supply(), 4)} #{ZcashExplorer.Swarm.ticker()}"

  defp format(value, decimals) when is_number(value),
    do: :erlang.float_to_binary(value + 0.0, [:compact, {:decimals, decimals}])

  defp format(_, _), do: "—"
end
