defmodule ZcashExplorerWeb.NetworkSolpsLive do
  @moduledoc """
  Network solution rate, in Equihash solutions per second.

  SWARM change: upstream printed whatever `getnetworksolps` returned. On a
  minimum-difficulty chain Zebra has been observed returning 0, and a "0" in a
  hash-rate card reads as a broken network rather than as "not measurable yet",
  so a non-positive reading shows an em dash instead. The unit is Sol/s:
  Equihash 200,9 is measured in solutions, never in hashes per second, so no
  H/s or GH/s wording appears anywhere.
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
      key: "NETWORK SOL/S",
      value: format(ZcashExplorer.Cache.get("networksolps")),
      note: "Equihash 200,9 solutions per second",
      accent: MetricCard.success()
    ]
  end

  # Zero is "the node has nothing to report", not a measurement.
  defp format(solps) when is_number(solps) and solps > 0 do
    :erlang.float_to_binary(solps + 0.0, [:compact, {:decimals, 2}])
  end

  defp format(_), do: "—"
end
