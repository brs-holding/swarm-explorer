defmodule ZcashExplorerWeb.TransactionController do
  alias ZcashExplorer.Rpc
  use ZcashExplorerWeb, :controller

  def get_transaction(conn, %{"txid" => txid}) do
    case Rpc.getrawtransaction(txid, 1) do
      {:ok, tx} ->
        tx_data =
          tx
          |> Zcashex.Transaction.from_map()
          |> enrich_vin()

        render(conn, "tx.html", tx: tx_data, page_title: "#{ZcashExplorer.Swarm.project_name()} transaction #{txid}")

      {:error, _reason} ->
        conn
        |> put_status(:not_found)
        |> render("not_found.html", txid: txid, page_title: "Transaction Not Found")
    end
  end

  # Bots poll this for transactions they have just broadcast, before this node
  # has seen them, so a miss is a routine 404 and not a 500.
  def get_raw_transaction(conn, %{"txid" => txid}) do
    {status, body} =
      case Rpc.getrawtransaction(txid, 1) do
        {:ok, tx} -> {200, tx}
        {:error, reason} -> {404, %{error: reason, txid: txid}}
      end

    conn
    |> put_resp_content_type("application/json")
    |> send_resp(status, Poison.encode!(body, pretty: true))
  end

  # Zebra's getrawtransaction never populates vin[].address/vin[].value (unlike
  # zcashd's insight-indexed RPC), so each spent output has to be resolved by
  # fetching its funding transaction and looking up the matching vout.
  defp enrich_vin(%Zcashex.Transaction{vin: vin} = tx_data) do
    %{tx_data | vin: Enum.map(vin, &enrich_input/1)}
  end

  defp enrich_input(%Zcashex.VInTX{address: address, value: value} = input)
       when not is_nil(address) and not is_nil(value) do
    input
  end

  defp enrich_input(%Zcashex.VInTX{txid: txid, vout: vout_index} = input)
       when is_binary(txid) and is_integer(vout_index) do
    case fetch_prevout(txid, vout_index) do
      %{"value" => value} = prevout ->
        address =
          prevout
          |> get_in(["scriptPubKey", "addresses"])
          |> List.wrap()
          |> List.first()

        %{input | value: value, address: address}

      _ ->
        input
    end
  end

  defp enrich_input(input), do: input

  defp fetch_prevout(txid, vout_index) do
    fallback = fn ->
      case Rpc.getrawtransaction(txid, 1) do
        {:ok, tx} -> {:commit, tx}
        {:error, _reason} -> {:ignore, nil}
      end
    end

    case Cachex.fetch(:app_cache, "rawtx:" <> txid, fallback) do
      {:ok, tx} -> find_vout(tx, vout_index)
      {:commit, tx} -> find_vout(tx, vout_index)
      _ -> nil
    end
  end

  defp find_vout(nil, _vout_index), do: nil

  defp find_vout(tx, vout_index) do
    tx
    |> Map.get("vout", [])
    |> Enum.find(fn out -> out["n"] == vout_index end)
  end
end
