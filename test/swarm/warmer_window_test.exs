defmodule ZcashExplorer.WarmerWindowTest do
  @moduledoc """
  The warmers must work on a chain that is only a few blocks long. Upstream's
  `(tip - 20)..tip` asks the node for negative heights below height 20.
  """
  use ExUnit.Case, async: true

  alias ZcashExplorer.WarmerWindow

  test "never asks for a negative height on a short chain" do
    for tip <- 0..25 do
      heights = WarmerWindow.heights(tip)
      assert Enum.min(heights) >= 0, "tip #{tip} produced #{inspect(heights)}"
      assert Enum.max(heights) == tip
    end
  end

  test "height 0 warms exactly the genesis block" do
    assert WarmerWindow.heights(0) == [0]
  end

  test "heights 0-10 stay inside the chain" do
    assert WarmerWindow.heights(10) == Enum.to_list(0..10)
  end

  test "a long chain warms the full window" do
    heights = WarmerWindow.heights(5_000)
    assert length(heights) == WarmerWindow.size()
    assert Enum.max(heights) == 5_000
  end

  test "an unknown tip warms nothing rather than crashing" do
    assert WarmerWindow.heights(nil) == []
    assert WarmerWindow.heights("loading...") == []
  end

  test "the interval is derived from the block target, not hardcoded at 15s" do
    # 75-second blocks -> 25 s, instead of upstream's 15 s.
    assert WarmerWindow.interval_ms() == 25_000
  end
end
