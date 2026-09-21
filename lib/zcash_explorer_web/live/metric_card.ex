defmodule ZcashExplorerWeb.MetricCard do
  @moduledoc """
  The metric card of the Swarm Style Guide explorer screen: a mono key, a Sora
  value, a note, and the flowing hairline along the top edge.

  Every metric LiveView on the home page delegates its `render/1` here so the
  eight cards cannot drift apart. Assigns: `key`, `value`, `note`, `accent`.

  A value the node cannot supply is rendered as an em dash by the caller. This
  module never invents one.
  """
  import Phoenix.LiveView.Helpers

  @doc "Renders one metric card."
  def card(assigns) do
    ~L"""
    <div class="sw-metric">
      <div class="sw-metric-flow"
           style="background:linear-gradient(90deg, transparent, <%= @accent %>, transparent);"></div>
      <div class="sw-key"><%= @key %></div>
      <div class="sw-value"><%= @value %></div>
      <div class="sw-note" style="color:<%= @accent %>;"><%= @note %></div>
    </div>
    """
  end

  @doc "Hive Orange: brand, primary action, shielded."
  def hive, do: "#FF8A1F"
  @doc "Honey: highlights and mining rewards."
  def honey, do: "#FFB020"
  @doc "Success green: confirmations and healthy readings."
  def success, do: "#3DD68C"
  @doc "Muted text. Used where a colour would imply a meaning the figure does not have."
  def muted, do: "#A89F92"
end
