defmodule ZcashExplorerWeb.LayoutView do
  @moduledoc """
  SWARM change: `bg_class/1` used to branch on mainnet vs testnet to pick a
  Tailwind palette. There is one network here, so the page background is a
  single token from the swarm.green design system.
  """
  use ZcashExplorerWeb, :view

  def bg_class(_assigns), do: "bg-swarm-cream dark:bg-swarm-hive"
end
