defmodule ZcashExplorer.WarmerWindow do
  @moduledoc """
  The range of heights the block and transaction warmers refetch, and how often.

  ## Why this exists (SWARM change)

  Upstream computes the window as `(tip - 20)..tip` and refetches it every 15
  seconds. Two problems on SwarmTestnet:

  1. **Short chains.** Below height 20 the range starts negative and every
     `getblock("-3", 2)` is a wasted round trip that the node rejects. A brand
     new network spends its first half hour there, and so does every CI run.
  2. **75-second blocks.** At mainnet's 75 s spacing a 15-second refresh of 21
     blocks plus 20 transactions is roughly 55 RPC calls per block produced,
     nearly all of them re-reading blocks that cannot have changed.

  The window is clamped at 0 and the interval defaults to a third of the block
  target, both overridable so an operator can trade freshness for node load.
  """

  @doc """
  Heights to warm for a given tip, clamped so a short chain never asks for a
  negative height. Returns `[]` when the tip is unknown.
  """
  def heights(tip) when is_integer(tip) and tip >= 0 do
    Enum.to_list(max(tip - size() + 1, 0)..tip)
  end

  def heights(_), do: []

  @doc "Number of blocks kept in the recent-block and recent-transaction lists."
  def size, do: config(:window, 21)

  @doc """
  Refresh interval in milliseconds. Defaults to a third of the configured block
  target (25 s for 75-second blocks), with a 5-second floor.
  """
  def interval_ms do
    case config(:interval_ms, nil) do
      ms when is_integer(ms) and ms > 0 ->
        ms

      _ ->
        max(div(ZcashExplorer.Swarm.block_target_seconds(), 3), 5) * 1000
    end
  end

  defp config(key, default) do
    Application.get_env(:zcash_explorer, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
