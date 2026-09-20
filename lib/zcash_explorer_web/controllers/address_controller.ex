defmodule ZcashExplorerWeb.AddressController do
  use ZcashExplorerWeb, :controller

  @tx_page_size 20

  # Shielded and unified addresses have no transparent balance or tx index, so
  # they must be routed away before any of the t-addr RPC calls below. These
  # used to be an `if` inside the transparent clauses whose `render/3` result
  # was discarded, so a z-addr fell through and crashed getaddressbalance/1.
  def get_address(conn, %{"address" => "zc" <> _ = address}), do: render_z_address(conn, address)
  def get_address(conn, %{"address" => "zs" <> _ = address}), do: render_z_address(conn, address)

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

  def get_ua(conn, %{"address" => "u" <> _ = ua}) do
    case Zcashex.z_listunifiedreceivers(ua) do
      {:ok, details} ->
        render(conn, "u_address.html",
          address: ua,
          qr: qr(ua),
          page_title: "Zcash Unified Address",
          orchard_present: Map.has_key?(details, "orchard"),
          transparent_present: Map.has_key?(details, "p2pkh"),
          sapling_present: Map.has_key?(details, "sapling"),
          details: details
        )

      {:error, _reason} ->
        invalid_address(conn, ua)
    end
  end

  def get_ua(conn, %{"address" => address}), do: invalid_address(conn, address)

  defp render_address(conn, address, s, e) do
    latest_block = latest_block()
    # if requesting for a block that's not yet mined, cap the request to the latest block
    capped_e = min(e, latest_block)

    with {:ok, balance} <- Zcashex.getaddressbalance(address),
         {:ok, txids} <- Zcashex.getaddresstxids(address, max(s, 0), capped_e) do
      render(conn, "address.html",
        address: address,
        balance: balance,
        txs: txids |> fetch_txs(address) |> Enum.reverse(),
        qr: qr(address),
        end_block: e,
        start_block: s,
        latest_block: latest_block,
        capped_e: capped_e,
        page_title: "Zcash Address #{address}"
      )
    else
      {:error, _reason} -> invalid_address(conn, address)
    end
  end

  defp render_z_address(conn, address) do
    render(conn, "z_address.html",
      address: address,
      qr: qr(address),
      page_title: "Zcash Shielded Address"
    )
  end

  # The template reads delta["satoshis"] and feeds it to zatoshi_to_zec/1, so
  # the sum has to come from "valueZat", not the ZEC-denominated "value".
  defp fetch_txs(txids, address) do
    Enum.flat_map(txids, fn txid ->
      case Zcashex.getrawtransaction(txid, 1) do
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
    |> render(:invalid_input, address: address)
  end
end
