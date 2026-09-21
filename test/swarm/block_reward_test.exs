defmodule ZcashExplorer.BlockRewardTest do
  @moduledoc """
  The four-way block reward breakdown, against a recorded `getblocksubsidy`
  reply that carries three funding-stream outputs.

  Regtest, which is what the end-to-end CI job runs, cannot carry funding
  streams, so this is the only place the relabelling and the shares are
  checked against real upstream field names.
  """
  use ExUnit.Case, async: true

  alias ZcashExplorer.Swarm

  @subsidy "test/fixtures/getblocksubsidy_swarm.json"
           |> File.read!()
           |> Jason.decode!()

  @block "test/fixtures/getblock_swarm.json"
         |> File.read!()
         |> Jason.decode!()

  describe "reward_breakdown/1" do
    setup do
      %{rows: Swarm.reward_breakdown(@subsidy)}
    end

    test "has exactly four rows: the miner and the three allocations", %{rows: rows} do
      assert length(rows) == 4
      assert Enum.map(rows, & &1.label) == [
               "Miner",
               "Core Development",
               "Grants & Ecosystem",
               "Community & Development Reserve"
             ]
    end

    test "relabels the upstream slot names", %{rows: rows} do
      # The point of the whole module: Zebra says "Electric Coin Company",
      # "Zcash Community Grants NU6" and "Zcash Foundation"; SWARM does not.
      labels = Enum.map(rows, & &1.label)
      refute "Electric Coin Company" in labels
      refute "Zcash Foundation" in labels
      refute "Zcash Community Grants NU6" in labels
      refute "Major Grants" in labels
    end

    test "amounts match the fixture and sum to the block subsidy", %{rows: rows} do
      by_label = Map.new(rows, fn row -> {row.label, row.amount} end)

      assert by_label["Miner"] == 5.0
      assert by_label["Core Development"] == 0.5
      assert by_label["Grants & Ecosystem"] == 0.25
      assert by_label["Community & Development Reserve"] == 0.5

      assert_in_delta Enum.sum(Enum.map(rows, & &1.amount)), 6.25, 1.0e-9
    end

    test "shares are 80 / 8 / 4 / 8 as specs/ECONOMICS.md requires", %{rows: rows} do
      by_label = Map.new(rows, fn row -> {row.label, row.share} end)

      assert_in_delta by_label["Miner"], 80.0, 1.0e-6
      assert_in_delta by_label["Core Development"], 8.0, 1.0e-6
      assert_in_delta by_label["Grants & Ecosystem"], 4.0, 1.0e-6
      assert_in_delta by_label["Community & Development Reserve"], 8.0, 1.0e-6
      assert_in_delta Enum.sum(Enum.map(rows, & &1.share)), 100.0, 1.0e-6
    end

    test "each allocation carries the destination address the node paid", %{rows: rows} do
      by_label = Map.new(rows, fn row -> {row.label, row.address} end)

      assert by_label["Miner"] == nil
      assert by_label["Core Development"] == "t2CoreDevelopmentFixtureAddress0001"
      assert by_label["Grants & Ecosystem"] == "t2GrantsEcosystemFixtureAddress0002"
      assert by_label["Community & Development Reserve"] == "t2CommunityReserveFixtureAddress003"
    end

    test "the pre-NU6 spelling of MajorGrants maps to the same label" do
      pre_nu6 = put_in(@subsidy, ["fundingstreams"], [
        %{"recipient" => "Major Grants", "value" => 0.25, "address" => "t2GrantsEcosystemFixtureAddress0002"}
      ])

      assert [_miner, grants] = Swarm.reward_breakdown(pre_nu6)
      assert grants.label == "Grants & Ecosystem"
    end

    test "a reply with no funding streams yields miner-only, not a crash" do
      regtest = %{"miner" => 6.25, "totalblocksubsidy" => 6.25, "founders" => 0.0}
      assert [%{label: "Miner", share: share}] = Swarm.reward_breakdown(regtest)
      assert_in_delta share, 100.0, 1.0e-6
    end

    test "nil and a zero subsidy yield an empty breakdown" do
      assert Swarm.reward_breakdown(nil) == []
      assert Swarm.reward_breakdown(%{}) == []
      assert Swarm.reward_breakdown(%{"miner" => 0, "totalblocksubsidy" => 0}) == []
    end
  end

  describe "rendering" do
    test "the block page's reward table names our labels, amounts and addresses" do
      html =
        Phoenix.View.render_to_string(ZcashExplorerWeb.BlockView, "basic_block.html",
          conn: Phoenix.ConnTest.build_conn(),
          project_name: Swarm.project_name(),
          network_name: Swarm.network_name(),
          ticker: Swarm.ticker(),
          block_data: @block,
          reward_breakdown: Swarm.reward_breakdown(@subsidy)
        )

      assert html =~ "Block reward"
      assert html =~ "Core Development"
      assert html =~ "Grants &amp; Ecosystem"
      assert html =~ "Community &amp; Development Reserve"
      # Amount, ticker and share of one allocation.
      assert html =~ "0.5 SWARM"
      assert html =~ "8.0%"
      # Destination addresses are linked.
      assert html =~ ~s|/address/t2CoreDevelopmentFixtureAddress0001|
      # The upstream slot names must not leak into the page.
      refute html =~ "Electric Coin Company"
      refute html =~ "Zcash Foundation"
    end
  end
end
