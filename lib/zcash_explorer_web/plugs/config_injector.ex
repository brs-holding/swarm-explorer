defmodule ZcashExplorerWeb.Plugs.ConfigInjector do
  @moduledoc """
  Makes the network identity available to every template.

  SWARM change: upstream read `zcash_network` ("mainnet" / "testnet") out of the
  Zcashex config and the templates branched on it to pick ZEC or TAZ, a
  mainnet/testnet cross-link and a page background. A private network is neither,
  so the assigns are now the configured name and ticker.
  """
  import Plug.Conn

  def init(default), do: default

  def call(conn, _opts) do
    conn
    |> assign(:network_name, ZcashExplorer.Swarm.network_name())
    |> assign(:ticker, ZcashExplorer.Swarm.ticker())
    |> assign(:project_name, ZcashExplorer.Swarm.project_name())
  end
end
