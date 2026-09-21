defmodule ZcashExplorerWeb.BlockView do
  alias ZcashExplorerWeb.TransactionView
  use ZcashExplorerWeb, :view

  def mined_time(nil) do
    "Not yet mined"
  end

  def mined_time(timestamp) do
    abs = timestamp |> Timex.from_unix() |> Timex.format!("{ISOdate} {ISOtime}")
    rel = timestamp |> Timex.from_unix() |> Timex.format!("{relative}", :relative)
    abs <> " " <> "(#{rel})"
  end

  def mined_time_without_rel(timestamp) do
    timestamp |> Timex.from_unix() |> Timex.format!("{ISOdate} {ISOtime}")
  end

  def mined_time_rel(timestamp) do
    timestamp |> Timex.from_unix() |> Timex.format!("{relative}", :relative)
  end

  def transaction_count(txs) do
    txs |> length()
  end

  def vin_count(txs) do
    txs |> Enum.reduce(0, fn x, acc -> length(x.vin) + acc end)
  end

  def vout_count(txs) do
    txs |> Enum.reduce(0, fn x, acc -> length(x.vout) + acc end)
  end

  def is_coinbase_tx?(nil), do: false

  def is_coinbase_tx?(tx) when tx.vin == [] do
    false
  end

  def is_coinbase_tx?(tx) when length(tx.vin) > 0 do
    first_tx = tx.vin |> List.first()

    case Map.fetch(first_tx, :coinbase) do
      {:ok, nil} -> false
      {:ok, _value} -> true
      :error -> false
    end
  end

  def get_coinbase_hex(tx) do
    tx
    |> Map.get(:vin)
    |> List.first()
    |> Map.get(:coinbase)
    |> decode_coinbase_tx_hex()

    # |> String.normalize(:nfkc)
  end

  def decode_coinbase_tx_hex(coinbase_hex)
      when is_binary(coinbase_hex) do
    try do
      coinbase_binary = Base.decode16!(coinbase_hex, case: :mixed)
      coinbase_list = :erlang.binary_to_list(coinbase_binary)
      List.to_string(coinbase_list)
    rescue
      _e in ArgumentError -> "unable to decode coinbase hex"
    end
  end

  # A shielded coinbase output has no scriptPubKey.addresses, so every hop here
  # has to tolerate nil instead of blowing up the whole block page.
  def mined_by(txs) do
    first_trx = List.first(List.wrap(txs))

    if is_coinbase_tx?(first_trx) do
      first_trx
      |> Map.get(:vout)
      |> List.wrap()
      |> List.first()
      |> get_field(:scriptPubKey)
      |> get_field(:addresses)
      |> List.wrap()
      |> List.first()
    end
  end

  defp get_field(nil, _key), do: nil
  defp get_field(map, key), do: Map.get(map, key)

  def input_total(txs) do
    [_hd | tail] = txs

    tail
    |> Enum.map(fn x -> Map.get(x, :vin) end)
    |> List.flatten()
    |> Enum.reduce(0, fn x, acc -> (Map.get(x, :value) || 0) + acc end)
    |> Kernel.+(0.0)
    |> :erlang.float_to_binary([:compact, {:decimals, 10}])
  end

  def output_total(txs) do
    txs
    |> Enum.map(fn x -> Map.get(x, :vout) end)
    |> List.flatten()
    |> Enum.reduce(0, fn x, acc -> (Map.get(x, :value) || 0) + acc end)
    |> Kernel.+(0.0)
    |> :erlang.float_to_binary([:compact, {:decimals, 10}])
  end

  def tx_out_total(%Zcashex.Transaction{} = tx) do
    tx
    |> Map.get(:vout)
    |> List.flatten()
    |> Enum.reduce(0, fn x, acc -> (Map.get(x, :value) || 0) + acc end)
    |> Kernel.+(0.0)
    |> :erlang.float_to_binary([:compact, {:decimals, 10}])
  end

  def tx_out_total(tx) when is_map(tx) do
    tx
    |> Map.get("vout")
    |> List.flatten()
    |> Enum.reduce(0, fn x, acc -> Map.get(x, "value") + acc end)
    |> Kernel.+(0.0)
    |> :erlang.float_to_binary([:compact, {:decimals, 10}])
  end

  # detect if a transaction is Public
  # https://z.cash/technology/
  def transparent_in_and_out(tx) do
    length(tx.vin) > 0 and length(tx.vout) > 0
  end

  def contains_sprout(tx) do
    length(tx.vjoinsplit) > 0
  end

  def contains_orchard(tx) do
    TransactionView.orchard_actions(tx) > 0
  end

  def contains_ironwood(tx) do
    TransactionView.ironwood_actions(tx) > 0
  end

  def get_joinsplit_count(tx) do
    length(tx.vjoinsplit)
  end

  def contains_sapling(tx) do
    value_balance = Map.get(tx, :valueBalance) || 0.0
    vshielded_spend = Map.get(tx, :vShieldedSpend) || []
    vshielded_output = Map.get(tx, :vShieldedOutput) || []
    value_balance != 0.0 and (length(vshielded_spend) > 0 || length(vshielded_output) > 0)
  end

  def is_shielded_tx?(tx) do
    !transparent_in_and_out(tx) and
      (contains_sprout(tx) or contains_sapling(tx) or contains_orchard(tx) or
         contains_ironwood(tx))
  end

  def is_transparent_tx?(tx) do
    value_balance = Map.get(tx, :valueBalance) || 0.0
    vshielded_spend = Map.get(tx, :vShieldedSpend) || []
    vshielded_output = Map.get(tx, :vShieldedOutput) || []

    transparent_in_and_out(tx) && length(tx.vjoinsplit) == 0 && value_balance == 0.0 &&
      length(vshielded_spend) == 0 && length(vshielded_output) == 0
  end

  def is_mixed_tx?(tx) do
    t_in_or_out = length(tx.vin) > 0 or length(tx.vout) > 0

    t_in_or_out and
      (contains_sprout(tx) || contains_sapling(tx) || contains_orchard(tx) ||
         contains_ironwood(tx))
  end

  def is_shielding(tx) do
    tin_and_zout = length(tx.vin) > 0 and length(tx.vout) == 0

    tin_and_zout and
      (contains_sprout(tx) || contains_sapling(tx) || contains_orchard(tx) ||
         contains_ironwood(tx))
  end

  def is_deshielding(tx) do
    zin_and_tout = length(tx.vin) == 0 and length(tx.vout) > 0

    zin_and_tout and
      (contains_sprout(tx) || contains_sapling(tx) || contains_orchard(tx) ||
         contains_ironwood(tx))
  end

  def tx_type(tx) do
    cond do
      is_coinbase_tx?(tx) ->
        "coinbase"

      is_mixed_tx?(tx) ->
        cond do
          is_shielding(tx) -> "shielding"
          is_deshielding(tx) -> "deshielding"
          true -> "mixed"
        end

      is_shielded_tx?(tx) ->
        "shielded"

      is_transparent_tx?(tx) ->
        "transparent"

      true ->
        "unknown"
    end
  end

  # --------------------------------------------------------------------------
  # SWARM additions: the privacy-aware presentation the Swarm Style Guide asks
  # for. Every figure below is computed from what the node actually returned;
  # none of it is a placeholder from the mockup.
  # --------------------------------------------------------------------------

  @doc """
  The share of this block's **non-coinbase** transactions that carry at least
  one shielded component (Sapling spends or outputs, Orchard actions, Ironwood
  actions, or a legacy joinsplit).

  Returns a float 0.0-100.0, or `nil` when the block contains nothing but its
  coinbase, in which case there is no honest number to show and the page shows
  an em dash. The coinbase is excluded because on this network it is produced
  by the protocol, not by a user making a privacy choice, so counting it would
  flatter or penalise the figure depending only on how the miner is paid.
  """
  def shielded_share(txs) do
    candidates =
      txs
      |> List.wrap()
      |> Enum.reject(&is_coinbase_tx?/1)

    case length(candidates) do
      0 ->
        nil

      total ->
        shielded = Enum.count(candidates, &has_shielded_component?/1)

        shielded / total * 100
    end
  end

  @doc "`shielded_share/1` rounded for display, or an em dash."
  def shielded_share_label(nil), do: "—"

  def shielded_share_label(share) when is_number(share),
    do: :erlang.float_to_binary(share + 0.0, [:compact, {:decimals, 1}]) <> "%"

  def shielded_share_label(txs), do: txs |> shielded_share() |> shielded_share_label()

  @doc "Bar width for the shielded-share indicator; an unknown share shows nothing."
  def shielded_share_width(nil), do: 0
  def shielded_share_width(share) when is_number(share), do: round(share)

  @doc """
  The state pill for a transaction: `:coinbase`, `:shielded` or `:revealed`.

  "Revealed" is the style guide's word for a transaction whose sender,
  recipient and amount are all public, and Clear Blue is reserved for exactly
  that. A transaction with any shielded component counts as shielded, because
  something in it is genuinely hidden.
  """
  def tx_state(tx) do
    cond do
      is_coinbase_tx?(tx) -> :coinbase
      has_shielded_component?(tx) -> :shielded
      true -> :revealed
    end
  end

  # Defensive on every field: upstream's contains_* helpers assume the decoded
  # struct always has a list where the RPC has one, and a nil from a trimmed or
  # future reply must not take a page down.
  defp has_shielded_component?(tx) do
    list = fn key -> tx |> Map.get(key) |> List.wrap() end

    length(list.(:vjoinsplit)) > 0 or
      length(list.(:vShieldedSpend)) > 0 or
      length(list.(:vShieldedOutput)) > 0 or
      (Map.get(tx, :valueBalance) || 0.0) != 0.0 or
      actions(tx, :orchard) > 0 or
      actions(tx, :ironwood) > 0
  end

  defp actions(tx, pool) do
    case Map.get(tx, pool) do
      %{actions: actions} when is_list(actions) -> length(actions)
      _ -> 0
    end
  end

  def tx_state_label(:coinbase), do: "COINBASE"
  def tx_state_label(:shielded), do: "SHIELDED"
  def tx_state_label(:revealed), do: "REVEALED"
  def tx_state_label(tx), do: tx |> tx_state() |> tx_state_label()

  def tx_state_class(:coinbase), do: "sw-pill sw-pill-coinbase"
  def tx_state_class(:shielded), do: "sw-pill sw-pill-shielded"
  def tx_state_class(:revealed), do: "sw-pill sw-pill-revealed"
  def tx_state_class(tx), do: tx |> tx_state() |> tx_state_class()

  @doc """
  What to print in the amount column.

  A shielded transaction has no public amount, so printing a number would be a
  lie: the transparent value of such a transaction is whatever leaked into or
  out of the pool, not what was sent. It is masked instead, which is the style
  guide's `⬢⬢⬢.⬢⬢`.
  """
  def display_amount(tx) do
    case tx_state(tx) do
      :shielded ->
        {:masked, "⬢⬢⬢.⬢⬢"}

      _ ->
        # Bare number; the caller adds the ticker, so a masked row can leave it
        # off entirely rather than printing "⬢⬢⬢.⬢⬢ SWM".
        {:public,
         tx |> tx_out_total_number() |> Kernel.+(0.0)
         |> :erlang.float_to_binary([:compact, {:decimals, 8}])}
    end
  end

  defp tx_out_total_number(tx) do
    tx
    |> Map.get(:vout, [])
    |> List.wrap()
    |> Enum.reduce(0, fn out, acc -> (Map.get(out, :value) || 0) + acc end)
  end
end
