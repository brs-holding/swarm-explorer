defmodule ZcashExplorerWeb.LayoutView do
  @moduledoc """
  SWARM change: `bg_class/1` branched on mainnet vs testnet to pick a Tailwind
  palette. There is one network and one theme here, so the page background is
  set once in the stylesheet and the helper is gone.
  """
  use ZcashExplorerWeb, :view
end
