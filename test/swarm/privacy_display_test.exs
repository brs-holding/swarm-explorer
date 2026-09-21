defmodule ZcashExplorerWeb.PrivacyDisplayTest do
  @moduledoc """
  The "real data only" rules of the Swarm Style Guide, as code.

  Two of them are correctness claims rather than styling, so they are tested:
  a shielded transaction must never be shown with a number, and the per-block
  shielded share must be computed from the block, not assumed.
  """
  use ExUnit.Case, async: true

  alias ZcashExplorerWeb.BlockView

  defp tx(overrides) do
    Map.merge(
      %{
        vin: [%{value: 1.0}],
        vout: [%{value: 0.9}],
        vjoinsplit: [],
        vShieldedSpend: [],
        vShieldedOutput: [],
        valueBalance: 0.0,
        version: 5,
        orchard: %{actions: [], valueBalance: 0.0},
        ironwood: nil
      },
      Map.new(overrides)
    )
  end

  defp coinbase, do: tx(vin: [%{coinbase: "0332243300"}], vout: [%{value: 6.25}])
  defp transparent, do: tx([])
  defp sapling, do: tx(vShieldedOutput: [%{}], valueBalance: -1.0)
  defp orchard, do: tx(orchard: %{actions: [%{}], valueBalance: -1.0})
  defp ironwood, do: tx(ironwood: %{actions: [%{}], valueBalance: -1.0})
  defp sprout, do: tx(vjoinsplit: [%{vpub_old: 1.0, vpub_new: 0.0}])

  describe "tx_state/1" do
    test "a coinbase is COINBASE, whatever else it carries" do
      assert BlockView.tx_state(coinbase()) == :coinbase
      assert BlockView.tx_state_label(coinbase()) == "COINBASE"
    end

    test "any shielded component makes it SHIELDED" do
      for t <- [sapling(), orchard(), ironwood(), sprout()] do
        assert BlockView.tx_state(t) == :shielded
      end
    end

    test "a fully transparent transaction is REVEALED" do
      assert BlockView.tx_state(transparent()) == :revealed
      assert BlockView.tx_state_label(transparent()) == "REVEALED"
    end

    test "Clear Blue is only ever used for REVEALED" do
      assert BlockView.tx_state_class(transparent()) =~ "revealed"
      refute BlockView.tx_state_class(sapling()) =~ "revealed"
      refute BlockView.tx_state_class(coinbase()) =~ "revealed"
    end

    test "a transaction missing fields does not take the page down" do
      assert BlockView.tx_state(%{vin: [], vout: []}) == :revealed
    end
  end

  describe "display_amount/1" do
    test "a shielded transaction is masked, never a number" do
      assert {:masked, glyphs} = BlockView.display_amount(sapling())
      refute glyphs =~ ~r/\d/
    end

    test "a transparent transaction shows its real output total" do
      assert {:public, "0.9"} = BlockView.display_amount(transparent())
    end

    test "a coinbase shows its real amount" do
      assert {:public, "6.25"} = BlockView.display_amount(coinbase())
    end
  end

  describe "shielded_share/1" do
    test "the coinbase is excluded from both sides of the ratio" do
      # One coinbase, one shielded and one transparent transaction: 50 %, not
      # 33 %, because the coinbase is not a user's privacy choice.
      assert_in_delta BlockView.shielded_share([coinbase(), sapling(), transparent()]),
                      50.0,
                      1.0e-9
    end

    test "a block with nothing but a coinbase has no honest share" do
      assert BlockView.shielded_share([coinbase()]) == nil
      assert BlockView.shielded_share_label(nil) == "—"
      assert BlockView.shielded_share_width(nil) == 0
    end

    test "all shielded is 100 %, none is 0 %" do
      assert BlockView.shielded_share([coinbase(), sapling(), orchard()]) == 100.0
      assert BlockView.shielded_share([coinbase(), transparent()]) == 0.0
    end

    test "an empty or unknown block list is nil rather than a crash" do
      assert BlockView.shielded_share([]) == nil
      assert BlockView.shielded_share(nil) == nil
    end

    test "the label is a percentage and the bar width an integer" do
      assert BlockView.shielded_share_label(50.0) == "50.0%"
      assert BlockView.shielded_share_width(66.6) == 67
    end
  end
end
