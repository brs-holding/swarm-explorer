defmodule ZcashExplorer.Swarm do
  @moduledoc """
  SWARM network facts and the block-reward allocation, all from configuration.

  Nothing here is hard-coded per deployment: the network display name, the
  ticker, the emission constants and the three allocation destinations are read
  from the application environment, which `config/runtime.exs` fills from
  environment variables (see `README-SWARM.md`).

  ## The allocation

  `specs/ECONOMICS.md` v0.4 fixes the split at 80 % miner, 8 % Core
  Development, 4 % Grants & Ecosystem, 8 % Community & Development Reserve.
  Zebra implements the three non-miner shares as upstream *funding streams*,
  whose recipient slots keep their Zcash names in the `getblocksubsidy` RPC.
  This module translates them:

  | Upstream slot     | `getblocksubsidy` recipient string                  | SWARM label                      |
  | ----------------- | --------------------------------------------------- | -------------------------------- |
  | `ECC`             | "Electric Coin Company"                             | Core Development                 |
  | `MajorGrants`     | "Major Grants" / "Zcash Community Grants NU6"        | Grants & Ecosystem               |
  | `ZcashFoundation` | "Zcash Foundation"                                  | Community & Development Reserve  |

  The post-NU6 spelling is the one SwarmTestnet produces, because every upgrade
  through NU6.3 is active from height 1; the pre-NU6 spelling is accepted too so
  the explorer also reads a chain configured differently.

  ## The network profile

  One image serves both networks. `network_kind/0` decides which, from
  `SWARM_NETWORK_KIND` when it is set and otherwise from the configured
  `network_name`: a name that says "test" is a test network, a name that says
  "main" is the mainnet, and **anything else is treated as a test network**, so
  a missing or misspelt setting keeps the "no value" warning rather than
  dropping it. `mainnet?/0` is what the templates branch on.
  """

  @type recipient :: %{
          slot: String.t(),
          label: String.t(),
          address: String.t() | nil,
          percent: number() | nil
        }

  # Upstream `FundingStreamReceiver::info/1` strings, mapped back to the slot
  # name used in Zebra's TOML. Verified in
  # zebra-chain/src/parameters/network/subsidy.rs at v6.3.0.
  @slot_aliases %{
    "ECC" => "ECC",
    "Electric Coin Company" => "ECC",
    "MajorGrants" => "MajorGrants",
    "Major Grants" => "MajorGrants",
    "Zcash Community Grants" => "MajorGrants",
    "Zcash Community Grants NU6" => "MajorGrants",
    "ZcashFoundation" => "ZcashFoundation",
    "Zcash Foundation" => "ZcashFoundation",
    "Deferred" => "Deferred",
    "Lockbox NU6" => "Deferred"
  }

  @default_recipients [
    %{slot: "ECC", label: "Core Development", address: nil, percent: 8},
    %{slot: "MajorGrants", label: "Grants & Ecosystem", address: nil, percent: 4},
    %{slot: "ZcashFoundation", label: "Community & Development Reserve", address: nil, percent: 8}
  ]

  # The SWARM label of each slot, so an allocation file that carries labels but
  # no slot names — the shape `swarm-mainnet render` writes — still lands in the
  # right slot. Derived from the defaults above; there is one list of labels.
  @label_slots Map.new(@default_recipients, fn r -> {r.label, r.slot} end)

  @doc "Display name of the network, e.g. \"SwarmTestnet\"."
  def network_name, do: config(:network_name, "SwarmTestnet")

  @doc """
  `:mainnet` or `:testnet`, for the templates that must not promise a test coin
  on a chain whose coins are real.

  `SWARM_NETWORK_KIND` (config key `:network_kind`) wins when it is set.
  Otherwise the configured `network_name` decides, and an unrecognised name is
  a test network: the warning is dropped only on a positive statement that this
  is the mainnet.
  """
  @spec network_kind() :: :mainnet | :testnet
  def network_kind do
    case config(:network_kind, nil) do
      kind when kind in [:mainnet, "mainnet"] -> :mainnet
      kind when kind in [:testnet, "testnet"] -> :testnet
      _ -> infer_kind(network_name())
    end
  end

  @doc "True only when this explorer is configured for the SWARM mainnet."
  @spec mainnet?() :: boolean()
  def mainnet?, do: network_kind() == :mainnet

  defp infer_kind(name) do
    down = name |> to_string() |> String.downcase()

    cond do
      String.contains?(down, "test") -> :testnet
      String.contains?(down, "main") -> :mainnet
      true -> :testnet
    end
  end

  @doc "Coin ticker for every public amount. The project is SWARM; the coin is SWM."
  def ticker, do: config(:ticker, "SWM")

  @doc "Short name of the project, used in titles."
  def project_name, do: config(:project_name, "SWARM")

  @doc "Maximum supply in coins, for the home page's issued-vs-maximum figure."
  def max_supply, do: config(:max_supply, 20_999_987.3152)

  @doc "Halving interval in blocks."
  def halving_interval, do: config(:halving_interval, 1_680_000)

  @doc "Target seconds between blocks; drives the cache warmer intervals."
  def block_target_seconds, do: config(:block_target_seconds, 75)

  @doc """
  The three configured allocation destinations.

  Falls back to the labels and percentages of `specs/ECONOMICS.md` with no
  address, so an explorer started without the destination configuration still
  renders a correct breakdown, just without linking the addresses.
  """
  @spec recipients() :: [recipient()]
  def recipients do
    case unwrap(config(:recipients, nil)) do
      list when is_list(list) and list != [] -> Enum.map(list, &normalise/1)
      _ -> @default_recipients
    end
  end

  @doc """
  The allocation out of already-decoded JSON, in either shape it is written in.

  A bare array — `[{"slot","label","address","percent"}]` — is what this
  explorer has always read. `%{"recipients" => [...]}` with `numerator` instead
  of `percent` and no `slot` is what `swarm-mainnet render` writes beside the
  node's own configuration. Both are accepted so that one allocation file
  serves the node and the explorer and the two cannot drift apart.
  """
  @spec unwrap(term()) :: list()
  def unwrap(%{"recipients" => list}) when is_list(list), do: list
  def unwrap(%{recipients: list}) when is_list(list), do: list
  def unwrap(list) when is_list(list), do: list
  def unwrap(_), do: []

  @doc "The recipient configured for an upstream slot name or recipient string."
  @spec recipient_for(String.t() | nil) :: recipient() | nil
  def recipient_for(nil), do: nil

  def recipient_for(name) do
    slot = Map.get(@slot_aliases, name, name)
    Enum.find(recipients(), fn r -> r.slot == slot end)
  end

  @doc """
  The SWARM label for an upstream `getblocksubsidy` recipient string.

  Unknown slots keep the upstream string rather than disappearing.
  """
  @spec label_for(String.t() | nil) :: String.t() | nil
  def label_for(nil), do: nil

  def label_for(name) do
    case recipient_for(name) do
      %{label: label} -> label
      nil -> name
    end
  end

  @doc """
  The allocation this address receives, or `nil`.

  Used by the address page to badge one of the three destination scripts.
  """
  @spec recipient_for_address(String.t() | nil) :: recipient() | nil
  def recipient_for_address(nil), do: nil

  def recipient_for_address(address) do
    Enum.find(recipients(), fn r -> r.address == address end)
  end

  @doc """
  Turns a `getblocksubsidy` reply into the rows of the "Block reward" table.

  Returns `[%{label, amount, share, address, slot}]`: the miner first, then one
  row per funding stream in the order Zebra reported them. `share` is the
  percentage of the total block subsidy, computed from the amounts rather than
  assumed, so a misconfigured chain shows the truth.

  Returns `[]` when the reply carries no usable numbers, which is what Regtest
  does: it has no funding streams at all.
  """
  @spec reward_breakdown(map() | nil) :: [map()]
  def reward_breakdown(nil), do: []

  def reward_breakdown(subsidy) when is_map(subsidy) do
    miner = number(subsidy["miner"])
    streams = List.wrap(subsidy["fundingstreams"]) ++ List.wrap(subsidy["lockboxstreams"])

    total =
      case number(subsidy["totalblocksubsidy"]) do
        t when is_number(t) and t > 0 -> t
        _ -> miner + Enum.reduce(streams, 0, fn s, acc -> acc + number(s["value"]) end)
      end

    if total > 0 do
      miner_row = %{
        slot: "Miner",
        label: "Miner",
        amount: miner,
        share: share(miner, total),
        address: nil
      }

      [miner_row | Enum.map(streams, &stream_row(&1, total))]
    else
      []
    end
  end

  def reward_breakdown(_), do: []

  defp stream_row(stream, total) do
    upstream = stream["recipient"]
    configured = recipient_for(upstream)
    amount = number(stream["value"])

    %{
      slot: Map.get(@slot_aliases, upstream, upstream),
      label: (configured && configured.label) || upstream,
      amount: amount,
      share: share(amount, total),
      # Prefer the address the node actually paid; fall back to configuration.
      address: stream["address"] || (configured && configured.address)
    }
  end

  defp share(_amount, total) when total in [0, 0.0, nil], do: 0.0
  defp share(amount, total), do: amount / total * 100

  @doc """
  The height of the next halving at or after `height`.

  Upstream halves at `floor((height + 1) / interval)`, so with Blossom active
  from height 1 the first halving lands on `interval - 1`.
  """
  def next_halving_height(height) when is_integer(height) and height >= 0 do
    interval = halving_interval()
    era = div(height + 1, interval)
    (era + 1) * interval - 1
  end

  def next_halving_height(_), do: nil

  @doc "Blocks remaining until `next_halving_height/1`."
  def blocks_to_halving(height) when is_integer(height) and height >= 0,
    do: next_halving_height(height) - height

  def blocks_to_halving(_), do: nil

  @doc "Percentage of the maximum supply that has been issued."
  def supply_percent(issued) when is_number(issued) do
    case max_supply() do
      max when is_number(max) and max > 0 -> issued / max * 100
      _ -> 0.0
    end
  end

  def supply_percent(_), do: 0.0

  @doc """
  The shielded value pools from `getblockchaininfo`, as `{id, chainValue}`.

  Transparent and the aggregate `chainSupply` entry are excluded; anything else
  the node reports (sapling, orchard, the NU6.3 Ironwood pool, lockbox) is kept,
  so a new pool appears without a code change.
  """
  def shielded_pools(value_pools) when is_list(value_pools) do
    value_pools
    |> Enum.reject(fn pool -> pool["id"] in ["transparent", "chainSupply", nil] end)
    |> Enum.map(fn pool -> {pool["id"], number(pool["chainValue"])} end)
  end

  def shielded_pools(_), do: []

  defp normalise(%{} = entry) do
    label = first([entry[:label], entry["label"]])

    slot =
      [entry[:slot], entry["slot"], entry[:upstream_slot], entry["upstream_slot"],
       entry[:receiver], entry["receiver"], Map.get(@label_slots, label)]
      |> first()
      |> to_string()

    %{
      slot: Map.get(@slot_aliases, slot, slot),
      label: label || slot,
      address: blank_to_nil(first([entry[:address], entry["address"]])),
      # `numerator` is the renderer's name for the same whole-percent share.
      percent: first([entry[:percent], entry["percent"], entry[:numerator], entry["numerator"]])
    }
  end

  defp first(values), do: Enum.find(values, fn v -> v != nil and v != "" end)

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp number(value) when is_number(value), do: value

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {float, _} -> float
      :error -> 0
    end
  end

  defp number(_), do: 0

  defp config(key, default) do
    Application.get_env(:zcash_explorer, __MODULE__, [])
    |> Keyword.get(key, default)
  end
end
