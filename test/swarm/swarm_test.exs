defmodule ZcashExplorer.SwarmTest do
  @moduledoc """
  Network identity, halving arithmetic, value pools and the address badge, all
  driven by configuration rather than constants in the source.
  """
  use ExUnit.Case, async: true

  alias ZcashExplorer.Swarm

  test "identity comes from configuration" do
    assert Swarm.ticker() == "SWARM"
    assert Swarm.network_name() == "SwarmTestnet"
    assert Swarm.block_target_seconds() == 75
  end

  describe "recipient_for/1" do
    test "accepts the upstream slot names Zebra's TOML uses" do
      assert Swarm.recipient_for("ECC").label == "Core Development"
      assert Swarm.recipient_for("MajorGrants").label == "Grants & Ecosystem"
      assert Swarm.recipient_for("ZcashFoundation").label == "Community & Development Reserve"
    end

    test "accepts the display strings getblocksubsidy returns" do
      assert Swarm.recipient_for("Electric Coin Company").label == "Core Development"
      assert Swarm.recipient_for("Zcash Community Grants NU6").label == "Grants & Ecosystem"
      assert Swarm.recipient_for("Major Grants").label == "Grants & Ecosystem"

      assert Swarm.recipient_for("Zcash Foundation").label ==
               "Community & Development Reserve"
    end

    test "an unknown slot keeps its upstream string rather than vanishing" do
      assert Swarm.recipient_for("Something Else") == nil
      assert Swarm.label_for("Something Else") == "Something Else"
      assert Swarm.label_for(nil) == nil
    end
  end

  describe "recipient_for_address/1" do
    test "badges a configured destination" do
      assert %{label: "Core Development", percent: 8} =
               Swarm.recipient_for_address("t2CoreDevelopmentFixtureAddress0001")
    end

    test "an ordinary address is not badged" do
      assert Swarm.recipient_for_address("tmEWLmZq9gYr3W5v4yJmRPnXTcPTZWnEXpn") == nil
      assert Swarm.recipient_for_address(nil) == nil
    end
  end

  describe "halving" do
    # Upstream halves at floor((height + 1) / interval). With a 1,680,000-block
    # interval and Blossom active from height 1 that puts the first halving at
    # 1,679,999 — specs/ECONOMICS.md v0.4 §3.
    test "the first halving is at interval - 1" do
      assert Swarm.next_halving_height(0) == 1_679_999
      assert Swarm.next_halving_height(1) == 1_679_999
      assert Swarm.next_halving_height(1_679_998) == 1_679_999
    end

    test "the second halving follows one interval later" do
      assert Swarm.next_halving_height(1_679_999) == 3_359_999
    end

    test "blocks remaining counts down to the next halving" do
      assert Swarm.blocks_to_halving(1_679_989) == 10
    end
  end

  describe "supply" do
    test "percent issued is against the configured maximum" do
      assert_in_delta Swarm.supply_percent(10_499_987.5), 49.99997, 1.0e-4
      assert Swarm.supply_percent(nil) == 0.0
    end
  end

  describe "shielded_pools/1" do
    test "keeps every shielded pool and drops transparent and the aggregate" do
      pools = [
        %{"id" => "transparent", "chainValue" => 10.0},
        %{"id" => "sprout", "chainValue" => 0.0},
        %{"id" => "sapling", "chainValue" => 1.5},
        %{"id" => "orchard", "chainValue" => 2.5},
        %{"id" => "ironwood", "chainValue" => 3.5},
        %{"id" => "chainSupply", "chainValue" => 17.5}
      ]

      assert Swarm.shielded_pools(pools) == [
               {"sprout", 0.0},
               {"sapling", 1.5},
               {"orchard", 2.5},
               {"ironwood", 3.5}
             ]
    end

    test "a missing or malformed list is empty, not a crash" do
      assert Swarm.shielded_pools(nil) == []
      assert Swarm.shielded_pools("loading...") == []
    end
  end
end
