defmodule ZcashExplorerWeb.CrashRegressionTest do
  @moduledoc """
  Covers the shapes that produced 500s in production: transactions whose
  pool/fee guards matched no clause, a shielded coinbase with no payout
  address, and zebrad's z_validateaddress reply.
  """
  use ExUnit.Case, async: true

  alias ZcashExplorerWeb.{BlockView, SearchController, TransactionView}

  describe "fee/pool helpers fall through instead of raising" do
    # Real shape of mainnet tx
    # 6f84eb33a16020bf226fd71c85556428c84a65d480e84eac2d8a6868b6beca0a as zebrad
    # returns it: shielded spends AND outputs with valueBalance exactly 0, which
    # matched no mixed_tx_fees/1 guard (they require valueBalance > 0 or < 0).
    @unhandled %{
      vjoinsplit: [],
      vin: [%{value: 3.3564e-4}],
      vout: [%{value: 8.564e-5}],
      vShieldedSpend: [%{}],
      vShieldedOutput: [%{}],
      valueBalance: 0.0,
      version: 5,
      orchard: %{actions: [], valueBalance: 0.0},
      ironwood: nil
    }

    test "mixed_tx_fees/1" do
      assert is_binary(TransactionView.mixed_tx_fees(@unhandled))
    end

    test "unknown_tx_fees/1" do
      assert is_binary(TransactionView.unknown_tx_fees(@unhandled))
    end

    test "shielding_tx_fee/1 and deshielding_tx_fees/1" do
      assert is_binary(TransactionView.shielding_tx_fee(@unhandled))
      assert is_binary(TransactionView.deshielding_tx_fees(@unhandled))
    end

    test "get_shielded_pool_label/1" do
      assert is_binary(TransactionView.get_shielded_pool_label(@unhandled))
    end

    test "get_shielded_pool_value/1 stays formattable" do
      value = TransactionView.get_shielded_pool_value(@unhandled)
      assert is_number(value)
      assert is_binary(TransactionView.format_zec(value))
    end
  end

  describe "mined_by/1" do
    test "returns nil for a coinbase with no transparent payout" do
      coinbase = %{
        vin: [%{coinbase: "0332243300"}],
        vout: [%{scriptPubKey: %{addresses: nil}}]
      }

      assert BlockView.mined_by([coinbase]) == nil
    end

    test "returns nil rather than raising on an empty block" do
      assert BlockView.mined_by([]) == nil
      assert BlockView.mined_by(nil) == nil
    end

    test "still reads the address when there is one" do
      coinbase = %{
        vin: [%{coinbase: "0332243300"}],
        vout: [%{scriptPubKey: %{addresses: ["t1abc"]}}]
      }

      assert BlockView.mined_by([coinbase]) == "t1abc"
    end
  end

  describe "ZcashExplorer.Cache with a cold cache" do
    # The mempool warmer refuses to run until zebrad reaches the tip, so during
    # a resync these keys stay unset and every {:ok, v} match used to succeed
    # with nil: length(nil) took down the home page.
    setup do
      {:ok, _} = Application.ensure_all_started(:cachex)
      name = :"cache_test_#{System.unique_integer([:positive])}"
      {:ok, _pid} = Cachex.start_link(name)
      %{cache: name}
    end

    test "a missing key reports an error instead of {:ok, nil}", %{cache: c} do
      assert ZcashExplorer.Cache.fetch("raw_mempool", c) == {:error, :missing}
    end

    test "get/3 falls back to the default", %{cache: c} do
      assert ZcashExplorer.Cache.get("raw_mempool", [], c) == []
      assert length(ZcashExplorer.Cache.get("raw_mempool", [], c)) == 0
      assert ZcashExplorer.Cache.get("metrics", %{}, c)["blocks"] == nil
    end

    test "field/3 is nil rather than a MatchError", %{cache: c} do
      assert ZcashExplorer.Cache.field("info", "build", c) == nil
    end

    test "a warmed key still comes back", %{cache: c} do
      Cachex.put(c, "metrics", %{"blocks" => 42})
      assert ZcashExplorer.Cache.fetch("metrics", c) == {:ok, %{"blocks" => 42}}
      assert ZcashExplorer.Cache.get("metrics", %{}, c)["blocks"] == 42
      assert ZcashExplorer.Cache.field("metrics", "blocks", c) == 42
    end
  end

  describe "search address predicates" do
    test "accepts zebrad's address_type key" do
      zebrad = {:ok, %{"isvalid" => true, "address_type" => "sapling"}}
      assert SearchController.is_valid_zaddr?(zebrad)
    end

    test "still accepts zcashd's type key" do
      zcashd = {:ok, %{"isvalid" => true, "type" => "sapling"}}
      assert SearchController.is_valid_zaddr?(zcashd)
    end

    test "unified addresses are not z-addresses" do
      ua = {:ok, %{"isvalid" => true, "address_type" => "unified"}}
      refute SearchController.is_valid_zaddr?(ua)
      assert SearchController.is_valid_unified_address?(ua)
    end

    test "a timed-out RPC is not a valid anything" do
      refute SearchController.is_valid_zaddr?({:error, :timeout})
      refute SearchController.is_valid_taddr?({:error, :timeout})
      refute SearchController.is_valid_block?({:error, :timeout})
      refute SearchController.is_valid_tx?({:error, :timeout})
      refute SearchController.is_valid_unified_address?({:error, :timeout})
    end
  end
end
