defmodule ZcashExplorerWeb.AddressController do
  alias ZcashExplorer.Rpc
  alias ZcashExplorer.Swarm
  use ZcashExplorerWeb, :controller

  @tx_page_size 20

  # Shielded and unified addresses have no transparent balance or tx index, so
  # they must be routed away before any of the t-addr RPC calls below. These
  # used to be an `if` inside the transparent clauses whose `render/3` result
  # was discarded, so a z-addr fell through and crashed getaddressbalance/1.
  #
  # SWARM change: upstream only matched the mainnet prefixes "zc", "zs" and "u".
  # SwarmTestnet uses testnet human-readable parts, so a Sapling address starts
  # "ztestsapling" and a unified address "utest". Transparent addresses are "tm"
  # (P2PKH) and "t2" (P2SH) and fall through to the transparent clauses below.
  def get_address(conn, %{"address" => "ztestsapling" <> _ = address}),
    do: render_z_address(conn, address)

  def get_address(conn, %{"address" => "zc" <> _ = address}), do: render_z_address(conn, address)
  def get_address(conn, %{"address" => "zs" <> _ = address}), do: render_z_address(conn, address)

  def get_address(conn, %{"address" => "swarm1" <> _ = address}),
    do: get_ua(conn, %{"address" => address})

  def get_address(conn, %{"address" => "utest" <> _ = address}),
    do: get_ua(conn, %{"address" => address})

  def get_address(conn, %{"address" => "u" <> _ = address}),
    do: get_ua(conn, %{"address" => address})

  def get_address(conn, %{"address" => address, "s" => s, "e" => e}) do
    with {:ok, s} <- parse_height(s),
         {:ok, e} <- parse_height(e) do
      render_address(conn, address, s, e)
    else
      :error -> invalid_address(conn, address)
    end
  end

  def get_address(conn, %{"address" => address}) do
    latest_block = latest_block()
    render_address(conn, address, latest_block - @tx_page_size, latest_block)
  end

  def get_ua(conn, %{"address" => address}) when is_binary(address) do
    if unified?(address) do
      case Rpc.z_listunifiedreceivers(address) do
        {:ok, details} ->
          render(conn, "u_address.html",
            address: address,
            qr: qr(address),
            page_title: "#{Swarm.project_name()} unified address",
            orchard_present: Map.has_key?(details, "orchard"),
            transparent_present: Map.has_key?(details, "p2pkh"),
            sapling_present: Map.has_key?(details, "sapling"),
            details: details
          )

        {:error, _reason} ->
          invalid_address(conn, address)
      end
    else
      invalid_address(conn, address)
    end
  end

  defp unified?("swarm1" <> _), do: true
  defp unified?("utest" <> _), do: true
  defp unified?("u" <> _), do: true
  defp unified?(_), do: false

  defp render_address(conn, address, s, e) do
    latest_block = latest_block()
    # if requesting for a block that's not yet mined, cap the request to the latest block
    capped_e = min(e, latest_block)

    with {:ok, balance} <- Rpc.getaddressbalance(address),
         {:ok, txids} <- Rpc.getaddresstxids(address, max(s, 0), capped_e) do
      render(conn, "address.html",
        address: address,
        balance: balance,
        txs: txids |> fetch_txs(address) |> Enum.reverse(),
        qr: qr(address),
        end_block: e,
        start_block: s,
        latest_block: latest_block,
        capped_e: capped_e,
        # SWARM change: badge the three block-reward destinations, which are
        # supplied by configuration rather than hard-coded here.
        allocation: Swarm.recipient_for_address(address),
        page_title: "#{Swarm.project_name()} address #{address}"
      )
    else
      {:error, _reason} -> invalid_address(conn, address)
    end
  end

  defp render_z_address(conn, address) do
    render(conn, "z_address.html",
      address: address,
      qr: qr(address),
      page_title: "#{Swarm.project_name()} shielded address"
    )
  end

  # The template reads delta["satoshis"] and feeds it to zatoshi_to_zec/1, so
  # the sum has to come from "valueZat", not the ZEC-denominated "value".
  defp fetch_txs(txids, address) do
    Enum.flat_map(txids, fn txid ->
      case Rpc.getrawtransaction(txid, 1) do
        {:ok, tx} -> [Map.put(tx, "satoshis", received_zat(tx, address))]
        {:error, _reason} -> []
      end
    end)
  end

  defp received_zat(tx, address) do
    tx
    |> Map.get("vout", [])
    |> Enum.map(fn
      %{"scriptPubKey" => %{"addresses" => [^address]}} = vout -> Map.get(vout, "valueZat", 0)
      _ -> 0
    end)
    |> Enum.sum()
  end

  defp latest_block do
    case ZcashExplorer.Cache.fetch("metrics") do
      {:ok, %{"blocks" => blocks}} -> blocks
      _ -> 0
    end
  end

  defp parse_height(value) do
    case Integer.parse(value) do
      {height, ""} when height >= 0 -> {:ok, height}
      _ -> :error
    end
  end

  defp qr(address) do
    address
    |> EQRCode.encode()
    |> EQRCode.png(width: 150, color: <<0, 0, 0>>, background_color: :transparent)
    |> Base.encode64()
  end

  defp invalid_address(conn, address) do
    conn
    |> put_status(:not_found)
    |> put_view(ZcashExplorerWeb.ErrorView)
    |> render(:invalid_input, query: address, page_title: "Nothing found")
  end
end
